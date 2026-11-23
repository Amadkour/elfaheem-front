// lib/features/games/templates/word_train/word_train.dart — Word Train (Games v4 T52, CONTRACT §2 `word_train`).
//
//   sequence / `order`   wagons with a word painted on them roll along the tracks of the landscape; the engine waits in a card on top
//                        with an empty coupling for every word. Tap the wagon in the order of the sentence: the right wagon
//                        rolls up and COUPLES to the train (a clack, a bump, the engine puffs), a wrong one wiggles and
//                        rolls on (nothing is lost). The wagons that were not needed leave, the next train comes.
//                        Long ayat come as segments (unit `segment`): each wagon carries one waqf segment (CONTRACT §9).
//
// Reports `s.answer(i, [slot, token])` for the FIRST try of every place only (CONTRACT §5); a retry is local.
//
// A sacred round (`session.sacred`, or an item of the Quran / Hadith): the calm theme, slow wagons, no timer, no lives, no
// red; a wrong wagon is a soft amber ring and the ayah plays AGAIN, then the learner tries again. The ayah is recited
// first, the replay button and the reciter chip sit in the card (CONTRACT §9). Quran words only through `quranTextStyle`.
//
//   WordTrainTemplate   the registry row
//   WordTrainHeader     plain values: the prompt, the engine and the couplings of the sentence, the replay / reciter buttons
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/floating_tokens.dart';
import 'package:flutter_education_app/features/games/bases/lane_runner.dart' show textIsRtl;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/templates/word_fishing/word_fishing.dart' show WordFishingRound, wordFishingSupports;

class WordTrainTemplate extends GameTemplate {
  const WordTrainTemplate({this.silent = false, this.reciters});

  /// No sounds or vibration (tests).
  final bool silent;
  final ReciterLoader? reciters;

  @override
  String get key => 'word_train';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.sequence};
  @override
  Set<ItemType> get accepts => const {ItemType.sequence};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'قطار الكلمات';
  @override
  String get nameEn => 'Word Train';
  @override
  IconData get icon => Icons.train_rounded;

  @override
  Widget build(GameSession s) => WordTrainView(session: s, silent: silent, reciters: reciters);
}

bool _sacredText(GameItem? it) => it != null && (it.sacred || it.sourceKind == 'quran' || it.sourceKind == 'hadith');

// ─────────────────────────────────────────────────────────────────────────────
//  The train card (plain values)
// ─────────────────────────────────────────────────────────────────────────────

/// The engine, drawn facing the way the train travels ([rtl]: to the left), with a chimney and a window.
class _EnginePainter extends CustomPainter {
  _EnginePainter(this.palette, this.rtl, this.outline);
  final GamePalette palette;
  final bool rtl;
  final double outline;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    canvas.save();
    if (rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width, h = size.height;
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2 * outline..color = p.ink;
    final red = Color.lerp(p.accent, p.ink, 0.12)!;
    final boiler = RRect.fromRectAndCorners(Rect.fromLTWH(w * 0.04, h * 0.3, w * 0.62, h * 0.5), topRight: const Radius.circular(18), topLeft: const Radius.circular(6), bottomLeft: const Radius.circular(6), bottomRight: const Radius.circular(18));
    final cab = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.62, h * 0.12, w * 0.34, h * 0.68), const Radius.circular(7));
    final roof = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.59, h * 0.06, w * 0.4, h * 0.1), const Radius.circular(4));
    final chim = Path()
      ..moveTo(w * 0.14, h * 0.32)
      ..lineTo(w * 0.17, h * 0.1)
      ..lineTo(w * 0.1, h * 0.04)
      ..lineTo(w * 0.34, h * 0.04)
      ..lineTo(w * 0.27, h * 0.1)
      ..lineTo(w * 0.3, h * 0.32)
      ..close();
    canvas.drawPath(chim, Paint()..color = p.ink.withValues(alpha: 0.85));
    for (final r in [boiler, cab]) {
      canvas.drawRRect(r, Paint()..shader = ui.Gradient.linear(r.outerRect.topCenter, r.outerRect.bottomCenter, [Color.lerp(red, p.paper, 0.3)!, red, Color.lerp(red, p.ink, 0.25)!], [0, 0.5, 1]));
      if (outline > 0.4) canvas.drawRRect(r, line);
    }
    canvas.drawRRect(roof, Paint()..color = p.ink.withValues(alpha: 0.8));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.69, h * 0.22, w * 0.2, h * 0.24), const Radius.circular(5)), Paint()..color = p.paper.withValues(alpha: 0.92));
    canvas.drawCircle(Offset(w * 0.04, h * 0.58), h * 0.1, Paint()..color = p.gold);
    canvas.drawRect(Rect.fromLTWH(w * 0.04, h * 0.78, w * 0.9, h * 0.06), Paint()..color = p.ink.withValues(alpha: 0.7));
    for (final (x, r) in [(w * 0.22, h * 0.15), (w * 0.52, h * 0.15), (w * 0.82, h * 0.12)]) {
      canvas.drawCircle(Offset(x, h * 0.86), r, Paint()..color = p.ink.withValues(alpha: 0.88));
      canvas.drawCircle(Offset(x, h * 0.86), r * 0.4, Paint()..color = p.gold);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EnginePainter o) => o.palette != palette || o.rtl != rtl || o.outline != outline;
}

/// A coupled wagon (or an empty coupling): the word's plate, the wheels and the links to its neighbours.
class _WagonPainter extends CustomPainter {
  _WagonPainter(this.palette, this.tone, this.done, this.next, this.outline);
  final GamePalette palette;
  final Color tone;
  final bool done, next;
  final double outline;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height - 12), const Radius.circular(9));
    final bar = Paint()..color = p.ink.withValues(alpha: done ? 0.7 : 0.25);
    canvas.drawRect(Rect.fromLTWH(-8, size.height - 22, 8, 4), bar);
    canvas.drawRect(Rect.fromLTWH(size.width, size.height - 22, 8, 4), bar);
    if (done) {
      canvas.drawRRect(body, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [Color.lerp(tone, p.paper, 0.3)!, tone], [0, 1]));
      if (outline > 0.4) canvas.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 2 * outline..color = p.ink);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(4, 4, size.width - 8, size.height - 20), const Radius.circular(6)), Paint()..color = p.paper.withValues(alpha: 0.94));
    } else {
      canvas.drawRRect(body, Paint()..color = p.ink.withValues(alpha: 0.05));
      canvas.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = next ? 2 : 1.2..color = next ? p.accent : p.ink.withValues(alpha: 0.2));
    }
    final wheel = Paint()..color = p.ink.withValues(alpha: done ? 0.88 : 0.3);
    final off = math.min(18.0, size.width / 4);
    for (final x in [off, size.width - off]) {
      canvas.drawCircle(Offset(x, size.height - 6), 6, wheel);
    }
  }

  @override
  bool shouldRepaint(_WagonPainter o) => o.palette != palette || o.done != done || o.next != next || o.tone != tone;
}

/// Puffs of steam rising and fading above the chimney.
class _SteamPainter extends CustomPainter {
  _SteamPainter(this.palette, this.rtl, this.t, this.calm);
  final GamePalette palette;
  final bool rtl, calm;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final f = (t + i / 3) % 1.0;
      final x0 = size.width * 0.22 + f * size.width * 0.2;
      final dx = rtl ? size.width - x0 : x0;
      paint.color = palette.paper.withValues(alpha: (calm ? 0.5 : 0.8) * (1 - f));
      canvas.drawCircle(Offset(dx, size.height * 0.04 - f * 14), 4 + f * 8, paint);
    }
  }

  @override
  bool shouldRepaint(_SteamPainter o) => o.t != t || o.rtl != rtl;
}

class WordTrainHeader extends StatefulWidget {
  const WordTrainHeader({
    super.key,
    required this.prompt,
    required this.words,
    required this.filled,
    required this.palette,
    this.quran = false,
    this.calm = false,
    this.outline = 1,
    this.actions = const [],
  });

  final String prompt;

  /// Every word of the sentence and how many wagons are coupled so far (the first [filled] words show).
  final List<String> words;
  final int filled;
  final GamePalette palette;
  final bool quran, calm;
  final double outline;

  /// The replay / reciter buttons.
  final List<Widget> actions;

  @override
  State<WordTrainHeader> createState() => _WordTrainHeaderState();
}

class _WordTrainHeaderState extends State<WordTrainHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _steam = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void dispose() {
    _steam.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _steam);
  }

  Color _tone(int i) {
    final p = widget.palette;
    final base = [p.accent2, p.accent, p.gold, Color.lerp(p.accent, p.paper, 0.4)!, Color.lerp(p.accent2, p.accent, 0.5)!][i % 5];
    return widget.calm ? Color.lerp(base, p.paper, 0.18)! : base;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette, words = widget.words;
    final rtl = words.isNotEmpty && textIsRtl(words.first);
    final reduce = appMotionOff(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paper.withValues(alpha: widget.calm ? 0.92 : 0.95),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: Color.lerp(palette.paper, palette.accent, 0.45)!, width: widget.calm ? 1 : 2),
            boxShadow: [BoxShadow(color: palette.ink.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.prompt.isNotEmpty)
                Text(widget.prompt,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(14, w: FontWeight.w700, c: palette.ink.withValues(alpha: 0.75), h: 1.4)),
              if (words.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: AppSpace.sm + 8,
                      runSpacing: AppSpace.xs,
                      children: [
                        _engine(rtl, reduce),
                        for (var i = 0; i < words.length; i++) _wagon(words[i], i, i < widget.filled, i == widget.filled, reduce),
                      ],
                    ),
                  ),
                ),
              if (widget.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, children: widget.actions),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// The engine with its steam (a few puffs rising from the chimney; still under Reduce motion).
  Widget _engine(bool rtl, bool reduce) {
    final p = widget.palette;
    return SizedBox(
      key: const ValueKey('train.engine'),
      width: 66,
      height: 52,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _steam,
          builder: (context, _) => CustomPaint(
            painter: _EnginePainter(p, rtl, widget.outline),
            foregroundPainter: _SteamPainter(p, rtl, reduce ? 0.35 : _steam.value, widget.calm),
          ),
        ),
      ),
    );
  }

  Widget _wagon(String word, int i, bool done, bool next, bool reduce) {
    final p = widget.palette;
    final style = widget.quran ? quranTextStyle(16, color: p.ink) : appText(18, w: FontWeight.w800, c: p.ink, h: 1.5);
    final card = CustomPaint(
      painter: _WagonPainter(p, _tone(i), done, next, widget.outline),
      child: Container(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.md),
        child: ExcludeSemantics(
          excluding: !done,
          child: Text(word, textAlign: TextAlign.center, style: done ? style : style.copyWith(color: const Color(0x00000000))),
        ),
      ),
    );
    // a coupled wagon rolls in with a small clack (a still wagon under Reduce motion)
    final key = ValueKey('place.$word.${done ? 1 : 0}');
    if (!done || reduce) return KeyedSubtree(key: key, child: card);
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: widget.calm ? 420 : 520),
      curve: widget.calm ? Curves.easeOut : Curves.elasticOut,
      builder: (context, v, child) => Transform.translate(
        offset: Offset((1 - v) * (Directionality.of(context) == TextDirection.rtl ? -22 : 22), 0),
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: card,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The page
// ─────────────────────────────────────────────────────────────────────────────

class WordTrainView extends StatefulWidget {
  const WordTrainView({super.key, required this.session, this.silent = false, this.reciters, this.advanceMs = 700});
  final GameSession session;
  final bool silent;
  final ReciterLoader? reciters;

  /// The pause between the last word and the next sentence (a sacred round waits longer so the ayah is heard whole).
  final int advanceMs;

  @override
  State<WordTrainView> createState() => WordTrainViewState();
}

class WordTrainViewState extends State<WordTrainView> {
  FloatingTokensGame? _game;
  AgeTheme? _theme;
  WordFishingRound? _round;
  int _item = -1, _slot = 0;
  final Set<int> _tried = {};
  final Set<int> _caught = {}; // fish
  bool _hint = false, _complete = false, _ready = false, _sacredGame = false;
  Timer? _timer;
  final GlobalKey _stack = GlobalKey(), _card = GlobalKey();

  GameSession get s => widget.session;
  FloatingTokensGame get game => _game!;
  WordFishingRound? get round => _round;
  int get itemIndex => _item;

  /// The place the next fish goes to.
  int get slot => _slot;
  bool get complete => _complete;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_game != null) return;
    final scope = AgeThemeScope.of(context);
    var age = scope.age;
    final forced = s.settings.theme;
    if (forced != 'auto') age = GameAge.values.firstWhere((a) => a.name == forced, orElse: () => scope.age);
    _sacredGame = s.sacred || s.items.any(_sacredText);
    final calm = s.calm || _sacredGame;
    _theme = (scope.age == age && scope.calm == calm)
        ? scope
        : AgeTheme.build(age, calm: calm, night: scope.night, primary: context.colors.primary);
    _game = FloatingTokensGame(theme: _theme!, skin: TokenSkin.train, motion: TokenMotion.drift, speed: s.settings.speed)
      ..onTap = _onTap
      ..onGone = _onGone;
    s.addListener(_onSession);
    _next();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      _timer?.cancel();
      _game?.pauseEngine();
      unawaited(_stopAudio());
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
      _caught.clear();
      _hint = false;
      _complete = false;
      _game!.setTopInset(null);
      _game!.setTokens(r.labels, quran: _sacredText(s.items[i]));
      _play();
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

  void _onTap(int fish) {
    final r = _round;
    if (r == null || _complete || s.finished || s.paused || _caught.contains(fish)) return;
    final place = _slot;
    final tok = r.ids[fish];
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
    final calm = _theme!.calm;
    GameFeedback.instance.answer(right, sacred: calm, silent: widget.silent);
    if (right) {
      _caught.add(fish);
      _game!.pop(fish, good: true);
      _slot++;
      if (_slot >= r.places) {
        _complete = true;
        // the whole sentence is heard once more in a sacred round, then the rest of the sea shrinks away
        if (_sacredText(s.items[_item])) _play();
        _later(_sacredText(s.items[_item]) ? widget.advanceMs + 900 : widget.advanceMs, () => _game!.release());
      }
      _refresh();
    } else {
      _game!.mark(fish);
      // a calm round: the ayah plays again so the right word is heard, then the learner tries again
      if (calm) _play();
    }
  }

  void _onGone() {
    if (s.finished || !_complete) return;
    _next();
  }

  void _hintPressed() {
    final r = _round;
    if (r == null || _complete) return;
    final f = r.fishFor(_slot, (k) => !_caught.contains(k) && _game!.isAlive(k));
    if (f < 0) return;
    _hint = true;
    _game!.hintToken(f);
  }

  // ---- the recitation ----

  bool get hasAudio => _item >= 0 && _item < s.items.length && stageSegments(s.items[_item]).isNotEmpty;

  void _play() {
    if (_item < 0 || _item >= s.items.length) return;
    final seg = stageSegments(s.items[_item]);
    if (seg.isEmpty) return;
    final r = s.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(seg, reciter: r is String ? r : null).catchError((Object _) {}));
  }

  // ---- the page ----

  /// Tells the game where the card ends so the rows of fish start below it.
  void _measure() {
    if (!mounted) return;
    final stack = _stack.currentContext?.findRenderObject();
    final card = _card.currentContext?.findRenderObject();
    if (stack is! RenderBox || card is! RenderBox || !stack.hasSize || !card.hasSize) return;
    final bottom = card.localToGlobal(Offset(0, card.size.height)).dy - stack.localToGlobal(Offset.zero).dy;
    _game?.setTopInset(bottom + AppSpace.xs);
  }

  @override
  Widget build(BuildContext context) {
    _ready = true;
    final theme = _theme!;
    final r = _round;
    final item = (_item >= 0 && _item < s.items.length) ? s.items[_item] : null;
    final lang = AppConfig.lang;
    final sf = StageSurface(theme, context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final page = GameSessionShell(
      session: s,
      kinds: const {MechanicKind.sequence},
      onHint: _hintPressed,
      silent: widget.silent,
      onScene: theme.onSky,
      overlay: true,
      child: Stack(key: _stack, children: [
        Positioned.fill(
          child: FloatingTokensView(
            game: _game!,
            semanticLabel: t('قطار الكلمات: اربط العربات بترتيبها', 'Word train: couple the wagons in order'),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.only(top: GameSessionShell.barHeight),
            child: KeyedSubtree(
              key: _card,
              child: WordTrainHeader(
                outline: theme.outline,
                prompt: item?.prompt.of(lang) ?? '',
                words: r?.words ?? const [],
                filled: _slot,
                palette: theme.palette,
                quran: _sacredText(item),
                calm: theme.calm,
                actions: hasAudio
                    ? [
                        StageListenButton(surface: sf, onPressed: _play),
                        StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: s.reciter?['key'] as String?),
                      ]
                    : const [],
              ),
            ),
          ),
        ),
        if (theme.calm && r != null && !_complete)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.lg),
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.palette.paper.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
                  child: Text(t('اختر العربة التالية', 'Tap the next wagon'), style: appText(13, w: FontWeight.w700, c: theme.palette.ink)),
                ),
              ),
            ),
          ),
      ]),
    );
    return _sacredGame ? quranFontGate(page) : page;
  }

}

/// The registry key of Word Train (`games.engine`).
const String kWordTrainKey = 'word_train';
