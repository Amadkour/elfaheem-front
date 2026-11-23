// lib/features/games/templates/space_rocket/space_rocket.dart — Space Rocket (Games v4 T46, CONTRACT §2 `space_rocket`).
//
//   choose    mcq / true_false: a planet hangs in every lane with an answer on it, fly the rocket through the right one
//
// It is Car Race's lane-runner base with the `space` skin: a starfield, a planet per lane, a rocket with a flame (the flame
// grows with every right answer). Controls: swipe (steer), tap a lane (go there), tilt (setting `tilt`).
//
// A calm round (sacred text, `session.calm`): the dawn palette, no speed lines, no shake, no red, no speed bonus (the planets
// wait for a tap on the lane), a quieter flame; a wrong planet dims, the ayah plays AGAIN and the same lanes wait for another try
// (every try is a trace entry; only the first scores, CONTRACT §5).
//
//   SpaceRocketHeader      plain values: the prompt, the replay and reciter buttons
//   SpaceRocketTemplate    the template (the gates come from Car Race's `buildCarGates`: the same fork, other scenery)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/lane_runner.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show quranFontGate, quranTextStyle;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/templates/car_race/car_race.dart' show CarGate, buildCarGates;

/// True when Space Rocket can play [item].
bool spaceRocketSupports(GameItem item) => item.type == ItemType.mcq || item.type == ItemType.trueFalse;

// ─────────────────────────────────────────────────────────────────────────────
//  The header (plain values)
// ─────────────────────────────────────────────────────────────────────────────

class SpaceRocketHeader extends StatelessWidget {
  const SpaceRocketHeader({super.key, required this.prompt, required this.palette, this.calm = false, this.quran = false, this.onReplay, this.onReciter});

  final String prompt;
  final bool calm;

  /// The prompt is Quran or Hadith text: drawn in the Quran role, wrapped whole, never clipped.
  final bool quran;
  final GamePalette palette;
  final VoidCallback? onReplay, onReciter;

  @override
  Widget build(BuildContext context) {
    final rtl = textIsRtl(prompt);
    final ink = palette.ink;
    final style = quran && rtl ? quranTextStyle(22, color: ink) : appText(20, w: FontWeight.w800, c: ink, h: 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paper.withValues(alpha: calm ? 0.92 : 0.95),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: Color.lerp(palette.paper, palette.accent, 0.45)!, width: calm ? 1 : 2),
            boxShadow: [BoxShadow(color: palette.ink.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Row(children: [
              if (onReplay != null)
                IconButton(
                  tooltip: t('أعد التلاوة', 'Hear it again'),
                  onPressed: onReplay,
                  icon: Icon(Icons.replay_rounded, color: palette.accent),
                ),
              Expanded(
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: quran
                      ? Text(prompt, textAlign: TextAlign.center, style: style)
                      : Text(prompt, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: style),
                ),
              ),
              if (onReciter != null)
                IconButton(
                  tooltip: t('غيّر القارئ', 'Change reciter'),
                  onPressed: onReciter,
                  icon: Icon(Icons.record_voice_over_rounded, color: palette.accent),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The template
// ─────────────────────────────────────────────────────────────────────────────

/// The registry key of Space Rocket (`games.engine`).
const String kSpaceRocketKey = 'space_rocket';

class SpaceRocketTemplate extends GameTemplate {
  const SpaceRocketTemplate({this.silent = false});

  /// No sounds or vibration (tests).
  final bool silent;

  @override
  String get key => kSpaceRocketKey;
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.choose};
  @override
  Set<ItemType> get accepts => const {ItemType.mcq, ItemType.trueFalse};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'صاروخ الفضاء';
  @override
  String get nameEn => 'Space Rocket';
  @override
  IconData get icon => Icons.rocket_launch_rounded;

  @override
  Widget build(GameSession s) => SpaceRocketView(session: s, silent: silent);
}

class SpaceRocketView extends StatefulWidget {
  const SpaceRocketView({super.key, required this.session, this.silent = false, this.tiltEvents});
  final GameSession session;
  final bool silent;
  final Stream<({double x, double y})>? tiltEvents;

  @override
  State<SpaceRocketView> createState() => SpaceRocketViewState();
}

class SpaceRocketViewState extends State<SpaceRocketView> {
  LaneRunnerGame? _game;
  AgeTheme? _theme;
  CarGate? _gate;
  int _item = -1;
  bool _hint = false, _retrying = false, _ready = false;

  GameSession get s => widget.session;

  /// The game (tests drive it).
  LaneRunnerGame get game => _game!;
  int get itemIndex => _item;
  CarGate? get currentGate => _gate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_game != null) return;
    final scope = AgeThemeScope.of(context);
    var age = scope.age;
    final forced = s.settings.theme;
    if (forced != 'auto') age = GameAge.values.firstWhere((a) => a.name == forced, orElse: () => scope.age);
    final calm = s.calm || s.sacred;
    _theme = (scope.age == age && scope.calm == calm)
        ? scope
        : AgeTheme.build(age, calm: calm, night: scope.night, primary: context.colors.primary);
    _game = LaneRunnerGame(theme: _theme!, speed: s.settings.speed, lanes: 3, skin: RunnerSkin.space)
      ..onChosen = _onChosen
      ..onResolved = _onResolved;
    s.addListener(_onSession);
    _nextItem();
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    unawaited(_stopAudio());
    super.dispose();
  }

  Future<void> _stopAudio() async {
    try {
      await GameAudio.instance.stopRecitation();
    } catch (_) {}
  }

  void _onSession() {
    if (s.finished) {
      _game?.pauseEngine();
      unawaited(_stopAudio());
    }
  }

  // ---- the flow ----

  static bool _sacredText(GameItem? it) => it != null && (it.sacred || it.sourceKind == 'quran' || it.sourceKind == 'hadith');

  RunnerGate _runnerGate(CarGate g) {
    final it = _item >= 0 && _item < s.items.length ? s.items[_item] : null;
    return RunnerGate(labels: g.labels, quran: _sacredText(it));
  }

  void _nextItem() {
    for (var i = _item + 1; i < s.items.length; i++) {
      if (!spaceRocketSupports(s.items[i])) continue;
      final gates = buildCarGates(s.items[i], seed: s.seed);
      if (gates.isEmpty) continue;
      _item = i;
      _gate = gates.first;
      _play();
      _present();
      return;
    }
    _item = s.items.length;
    _gate = null;
    if (!s.finished) s.finish('done');
    _refresh();
  }

  void _refresh() {
    if (mounted && _ready) setState(() {});
  }

  void _present() {
    _hint = false;
    _retrying = false;
    _game!.showGate(_runnerGate(_gate!));
    _refresh();
  }

  void _onChosen(int lane) {
    final g = _gate;
    if (g == null || _item >= s.items.length) return;
    final r = s.answer(_item, g.answer(lane), hint: _hint);
    if (r == null) {
      // the round is over or paused: nothing was recorded; show the same planets again
      if (!s.finished) _game!.showGate(_runnerGate(g));
      return;
    }
    _hint = false;
    final ok = g.isCorrect(lane);
    _retrying = !ok && _theme!.calm;
    _game!.resolve(correct: ok, correctLane: g.correctLane, retry: _retrying);
  }

  void _onResolved() {
    if (s.finished) return;
    if (_retrying) {
      // wrong in a calm round: the ayah again, the same planets wait
      _retrying = false;
      _play();
      return;
    }
    _nextItem();
  }

  void _hintPressed() {
    final g = _gate;
    if (g == null) return;
    _hint = true;
    _game!.hintLane(g.correctLane);
  }

  // ---- the ayah ----

  List<RecitationSegment> _segments() {
    if (_item < 0 || _item >= s.items.length) return const [];
    final a = s.items[_item].media.audio;
    if (a == null) return const [];
    return [for (final e in a) RecitationSegment(url: e.url, startMs: e.startMs, endMs: e.endMs, reciter: e.reciter, ref: e.ref)];
  }

  bool get hasAudio => _segments().isNotEmpty;

  void _play() {
    final seg = _segments();
    if (seg.isEmpty) return;
    unawaited(() async {
      try {
        await GameAudio.instance.playRecitation(seg, reciter: s.reciter?['key'] as String?);
      } catch (_) {}
    }());
  }

  Future<void> _reciter() async {
    GameReciterList list;
    try {
      list = await GameAudio.instance.loadReciters();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final r in list.items)
            ListTile(
              leading: Icon(r.key == (list.effective ?? list.mine) ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
              title: Text(AppConfig.lang == 'ar' ? r.nameAr : r.nameEn),
              onTap: () => Navigator.pop(ctx, r.key),
            ),
        ]),
      ),
    );
    if (key != null) {
      try {
        await GameAudio.instance.switchReciter(key);
      } catch (_) {}
    }
  }

  // ---- the page ----

  @override
  Widget build(BuildContext context) {
    _ready = true;
    final theme = _theme!;
    final item = (_item >= 0 && _item < s.items.length) ? s.items[_item] : null;
    final audio = hasAudio;
    final page = GameSessionShell(
      session: s,
      kinds: const {MechanicKind.choose},
      onHint: _hintPressed,
      silent: widget.silent,
      // the scene is always a dark sky: light text and icons on it
      onScene: theme.palette.paper,
      overlay: true,
      child: Stack(children: [
        Positioned.fill(
          child: LaneRunnerView(
            game: _game!,
            tilt: s.settings.tilt,
            tiltEvents: widget.tiltEvents,
            semanticLabel: t('صاروخ الفضاء: مرّ عبر الكوكب الصحيح', 'Space rocket: fly through the right planet'),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.only(top: GameSessionShell.barHeight),
            child: SpaceRocketHeader(
              prompt: item?.prompt.of(AppConfig.lang) ?? '',
              palette: theme.palette,
              calm: theme.calm,
              quran: _sacredText(item),
              onReplay: audio ? _play : null,
              onReciter: audio ? _reciter : null,
            ),
          ),
        ),
        if (theme.calm)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text(t('اضغط على الكوكب الذي تختاره', 'Tap the planet you choose'),
                  style: appText(13, w: FontWeight.w600, c: theme.palette.paper.withValues(alpha: 0.9))),
            ),
          ),
      ]),
    );
    return s.sacred ? quranFontGate(page) : page;
  }
}
