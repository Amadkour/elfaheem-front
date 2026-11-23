// lib/features/games/templates/car_race/car_race.dart — Car Race (Games v4 T38, CONTRACT §2 `car_race`).
//
//   choose    mcq / true_false: the road forks, every road has the answer on a sign above it, drive through one
//   sequence  `next_word` (the Quran mode): the ayah is recited, the words so far stand on top of the screen and the
//             road forks; every road has a word on its sign, the right one continues the ayah. The next fork is the next
//             word, until the ayah is whole.
//
// Controls: swipe (steer), tap a lane (go there), tilt (setting `tilt`).
//
// A calm round (sacred text, `session.calm`): the dawn palette, no speed lines, no shake, no red, NO speed bonus (the
// gate waits for a tap on the lane); a wrong road dims its sign, the ayah plays AGAIN and the same fork waits for another try
// (every try is a trace entry; only the first scores, CONTRACT §5). Otherwise a wrong road is a bump and the right sign
// lights up before the next fork.
//
//   CarGate / buildCarGates   pure: the forks of one item (labels per lane, the answer of every lane, which lane is right)
//   CarRaceHeader             plain values: the prompt, the words so far, the replay and reciter buttons
//   CarRaceTemplate           the template; `registerCarRaceTemplate()` adds it to `kGameTemplates`
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/lane_runner.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  The forks of an item (pure)
// ─────────────────────────────────────────────────────────────────────────────

/// One fork: [labels] left to right, [values] the thing each lane reports (an option index, 1 / 0, or a token index).
class CarGate {
  const CarGate({required this.labels, required this.values, required this.correct, this.slot = -1, this.phrase = ''});
  final List<String> labels;
  final List<int> values;

  /// The lanes that score (one, unless equal words are interchangeable).
  final Set<int> correct;

  /// The `sequence` slot this fork fills, -1 for a plain question.
  final int slot;

  /// The words already on the road (a `next_word` item).
  final String phrase;

  int get lanes => labels.length;
  int get correctLane => correct.first;
  bool isCorrect(int lane) => correct.contains(lane);

  /// The trace's `a` for a drive through [lane] (CONTRACT §5).
  Object answer(int lane) => slot >= 0 ? [slot, values[lane]] : values[lane];
}

/// True when Car Race can play [item] (`sequence` only in `next_word` mode).
bool carRaceSupports(GameItem item) {
  switch (item.type) {
    case ItemType.mcq:
    case ItemType.trueFalse:
      return true;
    case ItemType.sequence:
      return item.body['mode'] == 'next_word';
    default:
      return false;
  }
}

List<String> _strings(Object? v) => [for (final e in (v as List? ?? const [])) '$e'];

/// The forks of [item]: one for a question, one per `blanks` slot for a `next_word` sequence. [seed] orders the lanes of
/// a sequence (a question keeps the draw's own `show` order). At most 4 lanes, at least 2.
List<CarGate> buildCarGates(GameItem item, {int seed = 0, int maxLanes = 3}) {
  final b = item.body;
  switch (item.type) {
    case ItemType.trueFalse:
      final ans = b['answer'] == true || b['answer'] == 1;
      return [
        CarGate(labels: [t('صح', 'True'), t('خطأ', 'False')], values: const [1, 0], correct: {ans ? 0 : 1}),
      ];
    case ItemType.mcq:
      final opts = [for (final o in (b['options'] as List? ?? const [])) '${(o as Map)['text']}'];
      final answer = (b['answer'] as num).toInt();
      final order = item.show.where((i) => i >= 0 && i < opts.length).toList();
      final keep = <int>{answer};
      for (final i in order) {
        if (keep.length >= math.min(4, opts.length)) break;
        keep.add(i);
      }
      final lane = [for (final i in order) if (keep.contains(i)) i];
      return [CarGate(labels: [for (final i in lane) opts[i]], values: lane, correct: {lane.indexOf(answer)})];
    case ItemType.sequence:
      final tokens = _strings(b['tokens']);
      final extra = _strings(b['extra']);
      final eq = item.intList('eq');
      final n = tokens.length;
      final blanks = item.intList('blanks');
      final out = <CarGate>[];
      for (final slot in blanks) {
        if (slot < 0 || slot >= n) continue;
        final rng = math.Random(seed * 7919 + item.n * 131 + slot * 17 + 1);
        final others = <int>[
          for (var k = 0; k < extra.length; k++) if (extra[k] != tokens[slot]) n + k,
          ...([for (var j = 0; j < n; j++) if (j != slot && tokens[j] != tokens[slot] && (j >= eq.length || slot >= eq.length || eq[j] != eq[slot])) j]..shuffle(rng)),
        ];
        // a duplicate word is never offered twice
        final seen = <String>{tokens[slot]};
        final picked = <int>[slot];
        for (final o in others) {
          final w = o < n ? tokens[o] : extra[o - n];
          if (seen.add(w)) picked.add(o);
          if (picked.length >= maxLanes) break;
        }
        if (picked.length < 2) continue;
        picked.shuffle(rng);
        String word(int i) => i < n ? tokens[i] : extra[i - n];
        out.add(CarGate(
          labels: [for (final i in picked) word(i)],
          values: picked,
          correct: {picked.indexOf(slot)},
          slot: slot,
          phrase: tokens.sublist(0, slot).join(' '),
        ));
      }
      return out;
    default:
      return const [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The header (plain values)
// ─────────────────────────────────────────────────────────────────────────────

class CarRaceHeader extends StatelessWidget {
  const CarRaceHeader({
    super.key,
    required this.prompt,
    required this.palette,
    this.phrase = '',
    this.showBlank = false,
    this.calm = false,
    this.onReplay,
    this.onReciter,
  });

  final String prompt, phrase;

  /// A `next_word` item: the words so far end with a blank to fill.
  final bool showBlank;
  final bool calm;
  final GamePalette palette;
  final VoidCallback? onReplay, onReciter;

  @override
  Widget build(BuildContext context) {
    final rtl = textIsRtl(phrase.isEmpty ? prompt : phrase);
    final ink = palette.ink;
    final bare = phrase.isEmpty && !showBlank;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paper.withValues(alpha: calm ? 0.9 : 0.94),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: Color.lerp(palette.paper, palette.accent, 0.45)!, width: calm ? 1 : 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 5))],
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (prompt.isNotEmpty)
                    Text(prompt,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bare
                            ? appText(22, w: FontWeight.w800, c: ink, h: 1.5)
                            : appText(14, w: FontWeight.w600, c: ink.withValues(alpha: 0.72), h: 1.4)),
                  if (phrase.isNotEmpty || showBlank)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs),
                      child: Directionality(
                        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                        child: Text(
                          showBlank ? '$phrase …' : phrase,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: appText(26, w: FontWeight.w800, c: ink, h: 1.9),
                        ),
                      ),
                    ),
                ]),
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

class CarRaceTemplate extends GameTemplate {
  const CarRaceTemplate({this.silent = false});

  /// No sounds or vibration (tests).
  final bool silent;

  @override
  String get key => 'car_race';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.choose, MechanicKind.sequence};
  @override
  Set<ItemType> get accepts => const {ItemType.mcq, ItemType.trueFalse, ItemType.sequence};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'سباق السيارات';
  @override
  String get nameEn => 'Car Race';
  @override
  IconData get icon => Icons.directions_car_rounded;

  @override
  Widget build(GameSession s) => CarRaceView(session: s, silent: silent);
}

void registerCarRaceTemplate() => registerGameTemplate(const CarRaceTemplate());

class CarRaceView extends StatefulWidget {
  const CarRaceView({super.key, required this.session, this.silent = false, this.tiltEvents});
  final GameSession session;
  final bool silent;
  final Stream<({double x, double y})>? tiltEvents;

  @override
  State<CarRaceView> createState() => CarRaceViewState();
}

class CarRaceViewState extends State<CarRaceView> {
  LaneRunnerGame? _game;
  AgeTheme? _theme;
  List<CarGate> _gates = const [];
  int _item = -1, _gate = 0;
  bool _hint = false, _retrying = false, _ready = false;

  GameSession get s => widget.session;

  /// The game (tests drive it).
  LaneRunnerGame get game => _game!;
  int get itemIndex => _item;
  CarGate? get currentGate => _gate < _gates.length ? _gates[_gate] : null;

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
    _game = LaneRunnerGame(theme: _theme!, speed: s.settings.speed, lanes: 3)
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

  void _nextItem() {
    for (var i = _item + 1; i < s.items.length; i++) {
      if (!carRaceSupports(s.items[i])) continue;
      final gates = buildCarGates(s.items[i], seed: s.seed);
      if (gates.isEmpty) continue;
      _item = i;
      _gates = gates;
      _gate = 0;
      _play();
      _present();
      return;
    }
    _item = s.items.length;
    _gates = const [];
    if (!s.finished) s.finish('done');
    _refresh();
  }

  void _refresh() {
    if (mounted && _ready) setState(() {});
  }

  void _present() {
    final g = _gates[_gate];
    _hint = false;
    _retrying = false;
    _game!.showGate(RunnerGate(labels: g.labels));
    _refresh();
  }

  void _onChosen(int lane) {
    if (_item >= s.items.length || _gate >= _gates.length) return;
    final g = _gates[_gate];
    final r = s.answer(_item, g.answer(lane), hint: _hint);
    if (r == null) {
      // the round is over or paused: nothing was recorded; show the same fork again
      if (!s.finished) _game!.showGate(RunnerGate(labels: g.labels));
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
      // wrong in a calm round: the ayah again, the same fork waits
      _retrying = false;
      _play();
      return;
    }
    _gate++;
    if (_gate < _gates.length) {
      _present();
    } else {
      _nextItem();
    }
  }

  void _hintPressed() {
    final g = currentGate;
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
    final g = currentGate;
    final lang = AppConfig.lang;
    final audio = hasAudio;
    return GameSessionShell(
      session: s,
      kinds: kinds,
      onHint: _hintPressed,
      silent: widget.silent,
      child: Stack(children: [
        Positioned.fill(
          child: LaneRunnerView(
            game: _game!,
            tilt: s.settings.tilt,
            tiltEvents: widget.tiltEvents,
            semanticLabel: t('سباق السيارات: اختر الطريق الصحيح', 'Car race: drive through the right road'),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: CarRaceHeader(
            prompt: item?.prompt.of(lang) ?? '',
            phrase: g?.phrase ?? '',
            showBlank: g != null && g.slot >= 0,
            palette: theme.palette,
            calm: theme.calm,
            onReplay: audio ? _play : null,
            onReciter: audio ? _reciter : null,
          ),
        ),
        if (theme.calm)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text(t('اضغط على الطريق الذي تختاره', 'Tap the road you choose'),
                  style: appText(13, w: FontWeight.w600, c: theme.palette.paper.withValues(alpha: 0.9))),
            ),
          ),
      ]),
    );
  }

  static const Set<MechanicKind> kinds = {MechanicKind.choose, MechanicKind.sequence};
}

/// The registry key of Car Race (`games.engine`).
const String kCarRaceKey = 'car_race';
