// lib/features/games/templates/word_fishing/word_fishing.dart — Word Fishing (Games v4 T47, CONTRACT §2 `word_fishing`).
//
//   sequence / `order`   a sea of colourful fish, every fish carries a word (a letter, an ayah, a waqf segment); the
//                        sentence waits in a card on top with an empty place for every word. Tap the fish in the order of
//                        the sentence: the right fish swims up and its word lands in its place, a wrong one wiggles and
//                        swims on (nothing is lost). The fish that were not needed shrink away, the next sentence comes.
//
// Reports `s.answer(i, [slot, token])` for the FIRST try of every place only (CONTRACT §5); a retry is local.
//
// A sacred round (`session.sacred`, or an item of the Quran / Hadith): the calm theme, the tokens are PEARLS that drift
// slowly and never tilt, no timer, no lives, no red; a wrong pearl is a soft amber ring and the ayah plays AGAIN, then
// the learner tries again. The ayah is recited first, the replay button and the reciter chip sit in the card
// (CONTRACT §9). Quran words are drawn only through `quranTextStyle`.
//
//   WordFishingRound    pure: the words on the fish in the draw's `show` order and which fish fits which place
//   WordFishingHeader   plain values: the prompt, the places of the sentence, the replay / reciter buttons
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
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

class WordFishingTemplate extends GameTemplate {
  const WordFishingTemplate({this.silent = false, this.reciters});

  /// No sounds or vibration (tests).
  final bool silent;
  final ReciterLoader? reciters;

  @override
  String get key => 'word_fishing';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.sequence};
  @override
  Set<ItemType> get accepts => const {ItemType.sequence};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'صيد الكلمات';
  @override
  String get nameEn => 'Word Fishing';
  @override
  IconData get icon => Icons.set_meal_rounded;

  @override
  Widget build(GameSession s) => WordFishingView(session: s, silent: silent, reciters: reciters);
}

void registerWordFishingTemplate() => registerGameTemplate(const WordFishingTemplate());

/// True when Word Fishing can play [item]: a `sequence` in the mode `order`.
bool wordFishingSupports(GameItem item) => item.type == ItemType.sequence && (item.body['mode'] ?? 'order') == 'order';

bool _sacredText(GameItem? it) => it != null && (it.sacred || it.sourceKind == 'quran' || it.sourceKind == 'hadith');

/// One sentence as fish: fish `k` shows [labels]`[k]` and is the token [ids]`[k]` (the trace's token index).
class WordFishingRound {
  WordFishingRound._(this.words, this.labels, this.ids, this.eq);

  /// The sentence, one word per place (what the card shows once a place is filled).
  final List<String> words;
  final List<String> labels;
  final List<int> ids;
  final List<int> eq;

  int get places => words.length;

  factory WordFishingRound.of(GameItem item) {
    String text(Object? v) => '$v';
    final tokens = [for (final v in (item.body['tokens'] as List? ?? const [])) text(v)];
    final extra = [for (final v in (item.body['extra'] as List? ?? const [])) text(v)];
    final n = tokens.length;
    final eq = item.intList('eq');
    final order = item.show.where((i) => i >= 0 && i < n + extra.length).toList();
    return WordFishingRound._(
      tokens,
      [for (final k in order) k < n ? tokens[k] : extra[k - n]],
      order,
      eq.length >= n ? eq : [for (var i = 0; i < n; i++) i],
    );
  }

  /// True when token [tok] belongs in [place] (equal words are interchangeable).
  bool fits(int tok, int place) => tok < places && place < places && eq[tok] == eq[place];

  /// The fish (index in [labels]) that fits [place] and is still free, or -1.
  int fishFor(int place, bool Function(int fish) free) {
    for (var f = 0; f < ids.length; f++) {
      if (free(f) && fits(ids[f], place)) return f;
    }
    return -1;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The sentence card (plain values)
// ─────────────────────────────────────────────────────────────────────────────

class WordFishingHeader extends StatelessWidget {
  const WordFishingHeader({
    super.key,
    required this.prompt,
    required this.words,
    required this.filled,
    required this.palette,
    this.quran = false,
    this.calm = false,
    this.actions = const [],
  });

  final String prompt;

  /// Every word of the sentence and how many places are filled so far (the first [filled] words show).
  final List<String> words;
  final int filled;
  final GamePalette palette;
  final bool quran, calm;

  /// The replay / reciter buttons.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ink = palette.ink;
    final rtl = words.isNotEmpty && textIsRtl(words.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paper.withValues(alpha: calm ? 0.92 : 0.95),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: Color.lerp(palette.paper, palette.accent, 0.45)!, width: calm ? 1 : 2),
            boxShadow: [BoxShadow(color: ink.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (prompt.isNotEmpty)
                Text(prompt,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(14, w: FontWeight.w700, c: ink.withValues(alpha: 0.75), h: 1.4)),
              if (words.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xxs,
                      children: [
                        for (var i = 0; i < words.length; i++) _place(words[i], i < filled, i == filled),
                      ],
                    ),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, children: actions),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// A place of the sentence: the word once caught, else an empty slot of the same width (the next one is outlined).
  Widget _place(String word, bool done, bool next) {
    final style = quran ? quranTextStyle(16, color: palette.ink) : appText(18, w: FontWeight.w800, c: palette.ink, h: 1.5);
    final accent = calm ? palette.accent2 : palette.accent;
    return Container(
      key: ValueKey('place.$word.${done ? 1 : 0}'),
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        color: done ? Color.alphaBlend(accent.withValues(alpha: 0.2), palette.paper) : palette.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.block),
        border: Border.all(
          color: done ? accent.withValues(alpha: 0.7) : (next ? accent : palette.ink.withValues(alpha: 0.2)),
          width: next ? 2 : 1.2,
        ),
      ),
      child: ExcludeSemantics(
        excluding: !done,
        child: Text(word, textAlign: TextAlign.center, style: done ? style : style.copyWith(color: const Color(0x00000000))),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The page
// ─────────────────────────────────────────────────────────────────────────────

class WordFishingView extends StatefulWidget {
  const WordFishingView({super.key, required this.session, this.silent = false, this.reciters, this.advanceMs = 700});
  final GameSession session;
  final bool silent;
  final ReciterLoader? reciters;

  /// The pause between the last word and the next sentence (a sacred round waits longer so the ayah is heard whole).
  final int advanceMs;

  @override
  State<WordFishingView> createState() => WordFishingViewState();
}

class WordFishingViewState extends State<WordFishingView> {
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
    _game = FloatingTokensGame(theme: _theme!, skin: _sacredGame ? TokenSkin.pearl : TokenSkin.fish, motion: TokenMotion.drift, speed: s.settings.speed)
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
            semanticLabel: t('صيد الكلمات: اصطد الكلمات بترتيبها', 'Word fishing: catch the words in order'),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.only(top: GameSessionShell.barHeight),
            child: KeyedSubtree(
              key: _card,
              child: WordFishingHeader(
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
              padding: const EdgeInsets.only(bottom: AppSpace.xl),
              child: Text(t('اختر اللؤلؤة التالية', 'Tap the next pearl'), style: appText(13, w: FontWeight.w600, c: theme.palette.paper.withValues(alpha: 0.92))),
            ),
          ),
      ]),
    );
    return _sacredGame ? quranFontGate(page) : page;
  }

}

/// The registry key of Word Fishing (`games.engine`).
const String kWordFishingKey = 'word_fishing';
