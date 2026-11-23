// lib/features/games/templates/platform_jumper/platform_jumper.dart — Platform Jumper (Games v4 T53, CONTRACT §2 `platform_jumper`).
//
//   sequence / `order`   floating islands carry the words; the sentence is built in order. Tap an island and the jumper springs
//                        to it (a crouch, a stretched arc, a squash and a puff of dust on landing). The right island dips, takes
//                        a check and stays; a wrong one wobbles gently and the jumper hops back to where it was (the soft
//                        penalty is the session's: `soft` costs points, `lives` a life). When the sentence is whole the
//                        jumper drops to the ground, the rest of the islands shrink away and the next sentence comes.
//
// Reports `s.answer(i, [place, token])` for the FIRST try of every place only (CONTRACT §5); a retry is local.
//
// sacred_allowed is FALSE, fixed in code: [PlatformJumperTemplate.refuses] is true for a draw that holds a sacred item, and
// then the page shows a notice and NEVER reports an answer (a character must not jump on holy words, CONTRACT §2).
//
//   PlatformJumperTemplate   the registry row
//   jumpPose                 the pure squash-and-stretch arc of one jump (plain values, tested on its own)
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/floating_tokens.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/templates/balloon_pop/balloon_pop.dart' show BalloonPopRefused;
import 'package:flutter_education_app/features/games/templates/word_fishing/word_fishing.dart'
    show WordFishingHeader, WordFishingRound, wordFishingSupports;

class PlatformJumperTemplate extends GameTemplate {
  const PlatformJumperTemplate({this.silent = false});

  /// No sounds or vibration (tests).
  final bool silent;

  @override
  String get key => 'platform_jumper';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.sequence};
  @override
  Set<ItemType> get accepts => const {ItemType.sequence};

  /// Fixed in code (CONTRACT §2): no route can change it.
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'قفز المنصات';
  @override
  String get nameEn => 'Platform Jumper';
  @override
  IconData get icon => Icons.directions_run_rounded;

  /// True when [s] must not be played here: a sacred draw, or an item of the Quran or the Hadith.
  static bool refuses(GameSession s) =>
      s.sacred || s.items.any((i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith');

  @override
  Widget build(GameSession s) => refuses(s) ? const BalloonPopRefused() : PlatformJumperView(session: s, silent: silent);
}

/// The registry key of Platform Jumper (`games.engine`).
const String kPlatformJumperKey = 'platform_jumper';

/// One frame of a jump: where the feet are and how the body is squashed ([sx], [sy], scaled about the feet).
///
/// [u] runs 0..1: a crouch (0–0.14), the flight (0.14–0.86, a ballistic arc [lift] px high, stretched at take-off and
/// landing, round at the top), then the landing squash (0.86–1).
({Offset feet, double sx, double sy}) jumpPose(double u, Offset a, Offset b, double lift) {
  u = u.clamp(0.0, 1.0);
  if (u < 0.14) {
    final q = math.sin(u / 0.14 * math.pi / 2);
    final sy = 1 - 0.2 * q;
    return (feet: a, sx: 1 / sy, sy: sy);
  }
  if (u < 0.86) {
    final p = (u - 0.14) / 0.72;
    final e = p < 0.5 ? 2 * p * p : 1 - 2 * (1 - p) * (1 - p); // a soft ease along the ground
    final feet = Offset(a.dx + (b.dx - a.dx) * e, a.dy + (b.dy - a.dy) * p - 4 * lift * p * (1 - p));
    final sy = 1 + 0.16 * math.cos(p * math.pi).abs();
    return (feet: feet, sx: 1 / sy, sy: sy);
  }
  final q = (u - 0.86) / 0.14;
  final sy = 1 - 0.22 * math.sin(q * math.pi);
  return (feet: b, sx: 1 / sy, sy: sy);
}

class PlatformJumperView extends StatefulWidget {
  const PlatformJumperView({super.key, required this.session, this.silent = false, this.advanceMs = 700});
  final GameSession session;
  final bool silent;

  /// The pause between the last platform and the next sentence.
  final int advanceMs;

  @override
  State<PlatformJumperView> createState() => PlatformJumperViewState();
}

class PlatformJumperViewState extends State<PlatformJumperView> with TickerProviderStateMixin {
  FloatingTokensGame? _game;
  AgeTheme? _theme;
  WordFishingRound? _round;
  int _item = -1, _slot = 0;
  final Set<int> _tried = {};
  final Set<int> _done = {}; // islands reached
  bool _hint = false, _complete = false, _ready = false;
  Timer? _timer, _moodTimer;
  GameMood _mood = GameMood.idle;
  final GlobalKey _stack = GlobalKey(), _card = GlobalKey();
  Size _size = Size.zero;

  // the jumper: standing on island `_standing` (-1 = the ground), or in the air from `_from` to `_target`
  int _standing = -1, _good = -1, _target = -1;
  Offset _from = Offset.zero;
  bool _jumping = false, _slipping = false, _landed = false, _targetRight = false, _drop = false;
  late final AnimationController _jump = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))
    ..addListener(_onJump);
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  static const double _ground = 64;

  GameSession get s => widget.session;
  FloatingTokensGame get game => _game!;
  WordFishingRound? get round => _round;
  int get itemIndex => _item;

  /// The place the jumper is going for next.
  int get slot => _slot;
  bool get complete => _complete;

  /// The island the jumper stands on (-1 = the ground).
  int get standing => _standing;
  bool get busy => _jumping || _slipping;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _idle);
    if (_game != null) return;
    final scope = AgeThemeScope.of(context);
    var age = scope.age;
    final forced = s.settings.theme;
    if (forced != 'auto') age = GameAge.values.firstWhere((a) => a.name == forced, orElse: () => scope.age);
    final calm = s.calm;
    _theme = (scope.age == age && scope.calm == calm)
        ? scope
        : AgeTheme.build(age, calm: calm, night: scope.night, primary: context.colors.primary);
    _game = FloatingTokensGame(theme: _theme!, skin: TokenSkin.platforms, motion: TokenMotion.drift, speed: s.settings.speed)
      ..onTap = _onTap
      ..onGone = _onGone
      ..setBottomInset(_ground);
    s.addListener(_onSession);
    _next();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _moodTimer?.cancel();
    s.removeListener(_onSession);
    _jump.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _onSession() {
    if (s.finished) {
      _timer?.cancel();
      _game?.pauseEngine();
    }
  }

  // ---- the flow ----

  void _next() {
    for (var i = _item + 1; i < s.items.length; i++) {
      if (!wordFishingSupports(s.items[i])) continue;
      final r = WordFishingRound.of(s.items[i]);
      if (r.places < 2 || r.labels.length < r.places) continue;
      _item = i;
      _round = r;
      _slot = 0;
      _tried.clear();
      _done.clear();
      _hint = false;
      _complete = false;
      _standing = -1;
      _good = -1;
      _jumping = _slipping = _drop = false;
      _jump.stop();
      _game!.setTopInset(null);
      _game!.setTokens(r.labels);
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

  void _later(int ms, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: appMotionOff(context) ? ms ~/ 4 : ms), () {
      if (mounted) f();
    });
  }

  void _setMood(GameMood m, {int ms = 900}) {
    _moodTimer?.cancel();
    if (_mood != m) setState(() => _mood = m);
    if (m == GameMood.idle) return;
    _moodTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _mood = GameMood.idle);
    });
  }

  void _onTap(int i) {
    final r = _round;
    if (r == null || _complete || s.finished || s.paused || busy || _done.contains(i)) return;
    final place = _slot;
    final tok = r.ids[i];
    final right = r.fits(tok, place);
    if (_tried.add(place)) {
      final res = s.answer(_item, [place, tok], hint: _hint);
      if (res == null) {
        // paused or over: nothing was recorded, the place stays open
        _tried.remove(place);
        return;
      }
      _hint = false;
    }
    GameFeedback.instance.answer(right, sacred: false, silent: widget.silent);
    _startJump(i, right: right);
  }

  // ---- the jump ----

  Offset get _groundFeet => Offset(_size.width / 2, _size.height - _ground * 0.42);

  Offset _platformFeet(int i) => i < 0 ? _groundFeet : game.platformTop(i);

  /// Where the feet are right now.
  Offset get feet {
    if (_jumping) return _pose().feet;
    return _platformFeet(_standing);
  }

  ({Offset feet, double sx, double sy}) _pose() {
    final b = _platformFeet(_target);
    final lift = (math.max(36.0, (b - _from).distance * 0.34)).clamp(40.0, 150.0);
    return jumpPose(_jump.value, _from, b, lift);
  }

  void _startJump(int target, {required bool right, bool slip = false, int ms = 0}) {
    _from = feet;
    _target = target;
    _targetRight = right;
    _jumping = true;
    _slipping = slip;
    _landed = false;
    final base = ms > 0 ? ms : 640 - 40 * s.settings.speed;
    _jump.duration = Duration(milliseconds: appMotionOff(context) ? 1 : base);
    _jump.forward(from: 0);
  }

  void _onJump() {
    if (!_jumping) return;
    if (!_landed && _jump.value >= 0.86) {
      _landed = true;
      _land();
    }
    if (_jump.isCompleted) {
      _jumping = false;
      if (_drop) _drop = false;
      if (_slipping && _target == _good) _slipping = false;
      if (mounted) setState(() {});
    }
  }

  void _land() {
    final g = game;
    final at = _platformFeet(_target);
    if (_target >= 0) g.dust(at);
    if (_drop) {
      _standing = -1;
      return;
    }
    if (_slipping) {
      _standing = _target;
      return;
    }
    _standing = _target;
    if (_targetRight) {
      g.land(_target);
      _done.add(_target);
      _good = _target;
      _slot++;
      _setMood(GameMood.happy);
      final r = _round!;
      if (_slot >= r.places) {
        _complete = true;
        g.cheer(at);
        // the sentence is whole: a moment of cheer, then the jumper drops to the ground and the rest of the islands shrink away
        _later(widget.advanceMs, () {
          _drop = true;
          _startJump(-1, right: true, slip: false, ms: 400);
          g.release();
        });
      }
      _refresh();
    } else {
      g.mark(_target);
      _slipping = true;
      if (!_theme!.calm) _setMood(GameMood.sad, ms: 700);
      // the wrong island wobbles; the jumper hops back to where it was
      _later(420, () => _startJump(_good, right: false, slip: true));
    }
  }

  void _onGone() {
    if (s.finished || !_complete) return;
    _next();
  }

  void _hintPressed() {
    final r = _round;
    if (r == null || _complete) return;
    final f = r.fishFor(_slot, (k) => !_done.contains(k) && game.isAlive(k));
    if (f < 0) return;
    _hint = true;
    game.hintToken(f);
  }

  // ---- the page ----

  /// Tells the game where the card ends so the rows of islands start below it.
  void _measure() {
    if (!mounted) return;
    final stack = _stack.currentContext?.findRenderObject();
    final card = _card.currentContext?.findRenderObject();
    if (stack is! RenderBox || card is! RenderBox || !stack.hasSize || !card.hasSize) return;
    final bottom = card.localToGlobal(Offset(0, card.size.height)).dy - stack.localToGlobal(Offset.zero).dy;
    _game?.setTopInset(bottom + AppSpace.xs);
  }

  Widget _jumper(AgeTheme theme) {
    final side = (game.pitch * 0.66).clamp(54.0, 104.0);
    return AnimatedBuilder(
      animation: Listenable.merge([_jump, _idle]),
      builder: (context, _) {
        if (_size == Size.zero) return const SizedBox.shrink();
        final pose = _jumping ? _pose() : (feet: _platformFeet(_standing), sx: 1.0, sy: 1.0);
        return Positioned(
          left: pose.feet.dx - side / 2,
          top: pose.feet.dy - side * 0.9,
          width: side,
          height: side,
          child: IgnorePointer(
            child: Transform.scale(
              alignment: const Alignment(0, 0.8),
              scaleX: pose.sx,
              scaleY: pose.sy,
              child: GameCharacter(key: const ValueKey('jumper'), theme: theme, mood: _mood, size: side),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _ready = true;
    final theme = _theme!;
    final r = _round;
    final item = (_item >= 0 && _item < s.items.length) ? s.items[_item] : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return GameSessionShell(
      session: s,
      kinds: const {MechanicKind.sequence},
      onHint: _hintPressed,
      silent: widget.silent,
      onScene: theme.onSky,
      overlay: true,
      child: LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        return Stack(key: _stack, children: [
          Positioned.fill(
            child: FloatingTokensView(
              game: game,
              semanticLabel: t('قفز المنصات: اقفز على الكلمات بترتيبها', 'Platform jumper: jump on the words in order'),
            ),
          ),
          if (r != null) _jumper(theme),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.only(top: GameSessionShell.barHeight),
              child: KeyedSubtree(
                key: _card,
                child: WordFishingHeader(
                  prompt: item?.prompt.of(AppConfig.lang) ?? '',
                  words: r?.words ?? const [],
                  filled: _slot,
                  palette: theme.palette,
                  calm: theme.calm,
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}
