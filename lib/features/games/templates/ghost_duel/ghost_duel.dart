// lib/features/games/templates/ghost_duel/ghost_duel.dart — Ghost Duel (Games v4 T63, CONTRACT §8 "The duel"): a
// tug-of-war against the replayed trace of a real player of the same level and age band. `mcq` and `true_false`
// items on QuestionStage; never sacred (the registry row says `sacred_allowed: false` and the draw is refused here).
//
//   - every right answer pulls the rope toward the learner; the ghost pulls when ITS recorded right answers land
//     (the recorded `[ms, right]` steps replayed against the round's own clock: a pause stops the ghost too);
//   - with no ghost (`session.ghost == null`) the training partner plays: 70 % right at par pace, the server's numbers;
//   - the scene only DRAWS the race with the contract's share right; who won is the server's `duel.won`, shown on the
//     result (the play page sends `ghost_play_id` and never a verdict).
//   - kids: vivid and bouncy, teen: the night, adult: quiet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/question_stage.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/duel.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'duel_scene.dart';

class GhostDuelTemplate extends GameTemplate {
  const GhostDuelTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => 'ghost_duel';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.choose};
  @override
  Set<ItemType> get accepts => const {ItemType.mcq, ItemType.trueFalse};
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'مبارزة الظل';
  @override
  String get nameEn => 'Ghost Duel';
  @override
  IconData get icon => Icons.sports_kabaddi_rounded;

  @override
  Widget build(GameSession s) => refuses(s) ? const GhostDuelRefused() : GhostDuelGame(session: s, silent: silent);

  /// True when [s] must not be played here: a sacred draw, or an item of the Quran or the Hadith.
  static bool refuses(GameSession s) =>
      s.sacred || s.items.any((i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith');
}

/// What a sacred draw gets.
class GhostDuelRefused extends StatelessWidget {
  const GhostDuelRefused({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: context.colors.textMedium),
            AppSpace.gapSm,
            Text(t('هذه اللعبة لا تعرض النصوص المقدسة', 'This game never shows sacred text'),
                textAlign: TextAlign.center, style: appText(16, w: FontWeight.w600, c: context.colors.textMedium)),
          ]),
        ),
      );
}

const GhostDuelTemplate kGhostDuel = GhostDuelTemplate();

/// The rope's state at an instant (equality so the scene only rebuilds when something happened).
class DuelTick {
  const DuelTick({this.my = 0, this.myAnswered = 0, this.their = 0, this.theirAnswered = 0, this.kick = DuelKick.none, this.seq = 0});
  final int my, myAnswered, their, theirAnswered, seq;
  final DuelKick kick;

  @override
  bool operator ==(Object other) => other is DuelTick && other.my == my && other.myAnswered == myAnswered && other.their == their && other.theirAnswered == theirAnswered && other.seq == seq;
  @override
  int get hashCode => Object.hash(my, myAnswered, their, theirAnswered, seq);
}

class GhostDuelGame extends StatefulWidget {
  const GhostDuelGame({super.key, required this.session, this.silent = false, this.advanceMs = 1100, this.tickMs = 100});
  final GameSession session;
  final bool silent;
  final int advanceMs;

  /// How often the ghost's clock is read (a test makes it coarser or finer).
  final int tickMs;

  @override
  State<GhostDuelGame> createState() => _GhostDuelGameState();
}

class _GhostDuelGameState extends State<GhostDuelGame> {
  final QuestionStageController _stage = QuestionStageController();
  final ValueNotifier<DuelTick> _tick = ValueNotifier(const DuelTick());
  Timer? _timer;
  late final DuelGhost _ghost;
  int _seq = 0;

  GameSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _ghost = s.ghost ?? botDuelGhost(items: s.items.length, parMs: s.items.fold<int>(0, (a, b) => a + b.parSeconds) * 1000);
    _timer = Timer.periodic(Duration(milliseconds: widget.tickMs), (_) => _replay());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  /// The ghost's steps that have landed on the round's clock (paused time does not count).
  void _replay() {
    if (s.finished || s.paused) return;
    final now = s.elapsedMs;
    var n = 0, r = 0;
    for (final e in _ghost.events) {
      if (e.$1 > now) break;
      n++;
      r += e.$2 == 1 ? 1 : 0;
    }
    final v = _tick.value;
    if (n == v.theirAnswered) return;
    // the newest step decides the kick (several landing at once = the last one)
    final last = _ghost.events[n - 1].$2 == 1;
    _tick.value = DuelTick(
        my: v.my, myAnswered: v.myAnswered, their: r, theirAnswered: n, kick: last ? DuelKick.ghostPull : DuelKick.ghostSlip, seq: ++_seq);
  }

  void _mine(bool right) {
    final v = _tick.value;
    _tick.value = DuelTick(
        my: v.my + (right ? 1 : 0),
        myAnswered: v.myAnswered + 1,
        their: v.their,
        theirAnswered: v.theirAnswered,
        kick: right ? DuelKick.mePull : DuelKick.meSlip,
        seq: ++_seq);
  }

  Widget? _header(BuildContext context, GameItem it, StageSurface sf) {
    final tall = MediaQuery.sizeOf(context).height >= 700;
    final myTotal = s.items.length;
    final gTotal = _ghost.total;
    final name = _ghost.name.isEmpty ? t('شريك التدريب', 'Training partner') : _ghost.name;
    return ValueListenableBuilder<DuelTick>(
      valueListenable: _tick,
      builder: (context, v, _) => DuelScene(
        surface: sf,
        pos: (myTotal == 0 ? 0 : v.my / myTotal) - v.their / gTotal,
        myName: t('أنت', 'You'),
        ghostName: name,
        myCount: v.my,
        ghostCount: v.their,
        myTotal: myTotal,
        ghostTotal: gTotal,
        kick: v.kick,
        kickSeq: v.seq,
        height: tall ? 230 : 180,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AgeThemeScope.of(context);
    var age = scope.age;
    final forced = s.settings.theme;
    if (forced != 'auto') age = GameAge.values.firstWhere((a) => a.name == forced, orElse: () => scope.age);
    final theme = (age == scope.age) ? scope : AgeTheme.build(age, night: scope.night, primary: context.colors.primary);
    return AgeThemeScope(
      theme: theme,
      child: StageFrame(
        session: s,
        kinds: kGhostDuel.kinds,
        silent: widget.silent,
        onHint: _stage.hint,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
            child: QuestionStage(
              session: s,
              controller: _stage,
              silent: widget.silent,
              advanceMs: widget.advanceMs,
              header: _header,
              onRight: (_) => _mine(true),
              onWrong: (_) => _mine(false),
            ),
          ),
        ),
      ),
    );
  }
}
