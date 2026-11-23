// lib/features/games/templates/constellation/constellation.dart — Constellation (Games v4 T62, CONTRACT §2 `constellation`),
// our own game: a night sky where every star holds a word or an answer.
//
//   sequence   (`order`, `complete`, `next_word`) draw from star to star in the order of the words; a right link lights a
//              golden thread with a soft chime, a distractor star is wrong
//   pair       join each star to its partner (any order)
//   a finished set reveals a drawing (crescent, lantern, book) that flies into "my sky" at the bottom; the server adds it to
//   the learner's `profile.sky` with the play (nothing is promised here: the strip shows what this round added)
//
// Calm (a sacred set, `session.calm`): the dawn-teal night, no sparks, no shooting star, no penalty; a wrong try is a soft
// amber shimmer, a line "try again", and the AYAH REPLAYS so the right word is heard. The reciter quick switch sits in the
// header card, as in Verse Builder. Quran text is drawn only with `quranTextStyle` (laid out once in the Flame scene).
//
// Input: one finger drags from star to star, or taps them one by one (no drag needed). Every try is reported as the first try
// of its unit only (`[slot, token]` / `[a index, b index]`); a retry is local.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/flame_host.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';

import 'constellation_game.dart';
import 'constellation_round.dart';

class ConstellationTemplate extends GameTemplate {
  const ConstellationTemplate({this.silent = false, this.reciters, this.skyBase = 0});
  final bool silent;
  final ReciterLoader? reciters;

  /// Drawings the learner already has in their sky.
  final int skyBase;

  @override
  String get key => 'constellation';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.sequence, MechanicKind.pair};
  @override
  Set<ItemType> get accepts => const {ItemType.sequence, ItemType.pair};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'كوكبة';
  @override
  String get nameEn => 'Constellation';
  @override
  IconData get icon => Icons.auto_awesome_rounded;

  @override
  Widget build(GameSession s) => ConstellationView(session: s, silent: silent, reciters: reciters, skyBase: skyBase);
}

void registerConstellationTemplate() => registerGameTemplate(const ConstellationTemplate());

class ConstellationView extends StatefulWidget {
  const ConstellationView({super.key, required this.session, this.silent = false, this.reciters, this.skyBase = 0});
  final GameSession session;
  final bool silent;
  final ReciterLoader? reciters;
  final int skyBase;

  @override
  State<ConstellationView> createState() => ConstellationViewState();
}

class ConstellationViewState extends State<ConstellationView> {
  ConstellationGame? _game;
  AgeTheme? _theme;
  ConstellationRound? _round;
  int _item = -1, _setNo = 0, _streak = 0, _total = 0;
  final Set<int> _hinted = {};
  bool _ready = false;
  int? _pointer;
  final GlobalKey _stack = GlobalKey(), _card = GlobalKey();

  GameSession get s => widget.session;
  ConstellationGame get game => _game!;
  ConstellationRound? get round => _round;
  int get itemIndex => _item;
  bool get _calm => s.calm || s.sacred || s.items.any(ConstellationRound.isSacred);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_game != null) return;
    final scope = AgeThemeScope.of(context);
    var age = scope.age;
    if (s.settings.theme != 'auto') age = GameAge.values.firstWhere((a) => a.name == s.settings.theme, orElse: () => scope.age);
    _theme = AgeTheme.build(age, calm: _calm, night: true, primary: context.colors.primary);
    _total = s.items.where(ConstellationRound.handles).length;
    _game = ConstellationGame(theme: _theme!, skyBase: widget.skyBase)
      ..canPlay = (() => !s.finished && !s.paused)
      ..onTry = _onTry
      ..onRevealDone = _revealDone;
    s.addListener(_onSession);
    _next();
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    unawaited(GameAudio.instance.stopRecitation());
    super.dispose();
  }

  void _onSession() {
    if (s.finished) _game?.pauseEngine();
  }

  void _next() {
    for (var i = _item + 1; i < s.items.length; i++) {
      if (!ConstellationRound.handles(s.items[i])) continue;
      _item = i;
      _round = ConstellationRound.of(s.items[i]);
      _hinted.clear();
      _game!.setRound(_round!, top: 140, bottom: 56, shape: (s.seed + _setNo) % 3);
      _game!.setProgress(_setNo + 1, _total);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !s.finished) _play();
      });
      _refresh();
      return;
    }
    _item = s.items.length;
    _round = null;
    if (!s.finished) s.finish('done');
    _refresh();
  }

  void _refresh() {
    if (mounted && _ready) setState(() {});
  }

  bool get _hasAudio => _item >= 0 && _item < s.items.length && (s.items[_item].media.audio?.isNotEmpty ?? false);

  void _play() {
    if (_item < 0 || _item >= s.items.length) return;
    final segs = stageSegments(s.items[_item]);
    if (segs.isEmpty) return;
    final r = s.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(segs, reciter: r is String ? r : null).catchError((Object _) {}));
  }

  void _onTry(StarTry res, {required bool setDone}) {
    if (res.first) s.answer(_item, res.a, hint: _hinted.contains(res.unit));
    final calm = _calm;
    if (res.right) {
      _streak++;
      GameFeedback.instance.answer(true, streak: setDone ? 3 : _streak, sacred: calm, silent: widget.silent);
    } else {
      _streak = 0;
      if (calm) {
        GameFeedback.instance.answer(false, sacred: true, silent: widget.silent);
        _play();
      } else {
        GameFeedback.instance.play(GameSound.flip, silent: widget.silent);
      }
    }
  }

  void _revealDone() {
    _setNo++;
    _next();
  }

  void _hintPressed() {
    final r = _round;
    if (r == null || r.complete) return;
    final star = r.hintStar();
    if (star < 0) return;
    _hinted.add(r.isPair ? r.stars[star].ref : r.nextSlot);
    game.hint();
  }

  void _measure() {
    final stack = _stack.currentContext?.findRenderObject();
    final card = _card.currentContext?.findRenderObject();
    if (stack is! RenderBox || card is! RenderBox || !stack.hasSize || !card.hasSize) return;
    final bottom = card.localToGlobal(Offset(0, card.size.height)).dy - stack.localToGlobal(Offset.zero).dy;
    _game?.setField(top: bottom + AppSpace.sm, bottom: 56 + MediaQuery.paddingOf(context).bottom);
  }

  @override
  Widget build(BuildContext context) {
    _ready = true;
    final theme = _theme!;
    final night = game.night;
    final item = (_item >= 0 && _item < s.items.length) ? s.items[_item] : null;
    final sf = StageSurface(theme, context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final prompt = item?.prompt.of(AppConfig.lang) ?? '';
    final image = item?.media.image;
    final actions = <Widget>[
      if (_hasAudio) ...[
        StageListenButton(surface: sf, onPressed: _play),
        StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: s.reciter?['key'] as String?),
      ],
    ];
    final promptText = Text(
      prompt,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: appText(17, w: FontWeight.w700, c: night.text, h: 1.45),
    );
    final page = GameSessionShell(
      session: s,
      kinds: const {MechanicKind.sequence, MechanicKind.pair},
      onHint: _hintPressed,
      silent: widget.silent,
      onScene: theme.palette.paper,
      overlay: true,
      child: Stack(key: _stack, children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (_pointer != null) return;
              _pointer = e.pointer;
              game.pointerDown(e.localPosition);
            },
            onPointerMove: (e) {
              if (e.pointer == _pointer) game.pointerMove(e.localPosition);
            },
            onPointerUp: (e) {
              if (e.pointer != _pointer) return;
              _pointer = null;
              game.pointerUp(e.localPosition);
            },
            onPointerCancel: (e) {
              if (e.pointer != _pointer) return;
              _pointer = null;
              game.pointerCancel();
            },
            child: FlameHost(
              game: game,
              semanticLabel: t('كوكبة: صل النجوم بالترتيب الصحيح', 'Constellation: join the stars in the right order'),
              onReduceMotion: (v) => game.reduceMotion = v,
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.only(top: GameSessionShell.barHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xxs, AppSpace.sm, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                child: KeyedSubtree(
                  key: _card,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: night.chip.withValues(alpha: 0.74),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: night.gold.withValues(alpha: theme.calm ? 0.25 : 0.4)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (image != null && image.isNotEmpty) ...[
                            ClipOval(
                              child: SizedBox.square(
                                dimension: AppTouch.min,
                                child: Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                              ),
                            ),
                            AppSpace.gapXs,
                          ],
                          Flexible(child: promptText),
                        ]),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.xxs),
                          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: actions),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
    return (s.sacred || s.items.any(ConstellationRound.isSacred)) ? quranFontGate(page) : page;
  }
}
