// lib/features/games/templates/irab_hunter/irab_hunter.dart — I'rab Hunter (Games v4 T44, CONTRACT §2): `classify`
// items with `cases`. The words of one Arabic sentence sit in a tray; drag each word into its basket (noun, verb,
// particle, …). A word that has a case ending then asks for it: pick the case from a panel under the sentence.
//
//   - first 2-entry per word `s.answer(i, [token, bucket])`; first 3-entry `s.answer(i, [token, bucket, case])`
//     (only for a word that has a `case`, only after its bucket is right). A retry is local, never reported;
//   - a wrong basket shakes and the word flies back; a wrong case tints the tile and the learner tries again;
//   - tap works as well as drag: tap a word, then tap the basket in the row that appears (a screen reader, a mouse and
//     a finger that does not drag all play);
//   - hint: points at the basket (then the case) of the next word, and that word scores 0 (`h: true`);
//   - curated sentences only: sacred_allowed is FALSE, [IrabHunterTemplate.refuses] is true for a sacred draw and the
//     template then shows a notice instead of text.
// Arabic is drawn on a tall line (h 1.9) so a shadda + kasra never clips, and lays out right to left.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal, appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/drag_board.dart';
import 'package:flutter_education_app/features/games/bases/question_stage.dart' show StageClosing;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';

class IrabHunterTemplate extends GameTemplate {
  const IrabHunterTemplate();

  @override
  String get key => 'irab_hunter';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.classify};
  @override
  Set<ItemType> get accepts => const {ItemType.classify};
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'صيّاد الإعراب';
  @override
  String get nameEn => "I'rab Hunter";
  @override
  IconData get icon => Icons.travel_explore_rounded;

  /// True when [s] must not be played here: a sacred draw, or an item of the Quran or the Hadith.
  static bool refuses(GameSession s) =>
      s.sacred || s.items.any((i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith');

  @override
  Widget build(GameSession s) => refuses(s) ? const IrabHunterRefused() : IrabHunterGame(session: s);
}

const IrabHunterTemplate kIrabHunter = IrabHunterTemplate();

/// What a sacred draw gets.
class IrabHunterRefused extends StatelessWidget {
  const IrabHunterRefused({super.key});

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

/// One word of the sentence.
class IrabWord {
  const IrabWord(this.text, this.bucket, this.caseKey);
  final String text;
  final String bucket;
  final String? caseKey;
}

/// The parts of a `classify` item this game reads (plain values, no widgets).
class IrabRound {
  IrabRound._(this.words, this.buckets, this.bucketKeys, this.cases, this.caseKeys);
  final List<IrabWord> words;
  final List<String> buckets, bucketKeys, cases, caseKeys;

  factory IrabRound.of(GameItem it) {
    final b = it.body;
    final bl = (b['buckets'] as List? ?? const []).whereType<Map>().toList();
    final cl = (b['cases'] as List? ?? const []).whereType<Map>().toList();
    return IrabRound._(
      [
        for (final w in (b['tokens'] as List? ?? const []).whereType<Map>())
          IrabWord('${w['text']}', '${w['bucket']}', w['case'] == null ? null : '${w['case']}'),
      ],
      [for (final x in bl) stageText(x['label'])],
      [for (final x in bl) '${x['key']}'],
      [for (final x in cl) stageText(x['label'])],
      [for (final x in cl) '${x['key']}'],
    );
  }

  int bucketOf(int tok) => bucketKeys.indexOf(words[tok].bucket);
  int? caseOf(int tok) {
    final c = words[tok].caseKey;
    return c == null ? null : caseKeys.indexOf(c);
  }

  bool needsCase(int tok) => cases.isNotEmpty && words[tok].caseKey != null;
}

class IrabHunterGame extends StatefulWidget {
  const IrabHunterGame({super.key, required this.session, this.silent = false, this.advanceMs = 1100});
  final GameSession session;
  final bool silent;
  final int advanceMs;

  @override
  State<IrabHunterGame> createState() => _IrabHunterGameState();
}

class _IrabHunterGameState extends State<IrabHunterGame> {
  int _i = 0;
  bool _done = false, _locked = false;
  late IrabRound _r = IrabRound.of(s.items.first);

  final Map<int, int> _placed = {}; // token -> bucket (right ones)
  final Map<int, int> _cased = {}; // token -> case (right ones)
  final Set<int> _triedB = {}, _triedC = {};
  int _pending = -1; // the word whose case is asked
  int _sel = -1; // the word picked by a tap
  int _wrongSlot = -1, _wrongTok = -1, _shake = 0, _wrongCase = -1;
  int _hintTok = -1;
  int _streak = 0;
  GameMood _mood = GameMood.idle;
  Timer? _timer, _wrongTimer;

  GameSession get s => widget.session;
  GameItem get item => s.items[_i];

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wrongTimer?.cancel();
    s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (s.finished && !_done && mounted) setState(() => _done = true);
  }

  void _later(int ms, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: appMotionOff(context) ? ms ~/ 4 : ms), () {
      if (mounted) f();
    });
  }

  bool _finishedWord(int k) => _placed.containsKey(k) && (!_r.needsCase(k) || _cased.containsKey(k));

  /// The next word of the sentence that is not finished, in reading order.
  int get _nextWord {
    for (var k = 0; k < _r.words.length; k++) {
      if (!_finishedWord(k)) return k;
    }
    return -1;
  }

  void _advance() {
    if (s.finished) {
      setState(() => _done = true);
      return;
    }
    if (_i + 1 >= s.items.length) {
      setState(() => _done = true);
      s.finish('done');
      return;
    }
    setState(() {
      _i++;
      _r = IrabRound.of(item);
      _placed.clear();
      _cased.clear();
      _triedB.clear();
      _triedC.clear();
      _pending = _sel = _hintTok = -1;
      _wrongSlot = _wrongTok = _wrongCase = -1;
      _locked = false;
      _mood = GameMood.idle;
    });
  }

  void _hint() {
    if (_locked || _done || _hintTok >= 0) return;
    final w = _pending >= 0 ? _pending : [for (final k in item.show) if (!_placed.containsKey(k)) k].firstOrNull ?? -1;
    if (w < 0) return;
    HapticFeedback.selectionClick();
    setState(() => _hintTok = w);
  }

  void _react(bool good) {
    GameFeedback.instance.answer(good, streak: good ? ++_streak : (_streak = 0), sacred: false, silent: widget.silent);
    _mood = good ? GameMood.happy : GameMood.sad;
    good ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
  }

  void _drop(int tok, int bucket) {
    if (_locked || _done || _pending >= 0 || _placed.containsKey(tok) || _wrongSlot >= 0) return;
    if (tok < 0 || tok >= _r.words.length || bucket < 0 || bucket >= _r.buckets.length) return;
    final right = bucket == _r.bucketOf(tok);
    if (_triedB.add(tok)) s.answer(_i, [tok, bucket], hint: _hintTok == tok);
    if (right) {
      _react(true);
      setState(() {
        _placed[tok] = bucket;
        _sel = -1;
        if (_r.needsCase(tok)) {
          _pending = tok;
        } else {
          if (_hintTok == tok) _hintTok = -1;
          _checkDone();
        }
      });
    } else {
      _react(false);
      setState(() {
        _wrongSlot = bucket;
        _wrongTok = tok;
        _shake++;
        _sel = -1;
      });
      _wrongTimer?.cancel();
      _wrongTimer = Timer(Duration(milliseconds: appMotionOff(context) ? 150 : 720), () {
        if (mounted) setState(() => _wrongSlot = _wrongTok = -1);
      });
    }
  }

  void _pickCase(int c) {
    final tok = _pending;
    if (tok < 0 || _locked || _done || _wrongCase >= 0) return;
    if (_triedC.add(tok)) s.answer(_i, [tok, _placed[tok]!, c], hint: _hintTok == tok);
    if (c == _r.caseOf(tok)) {
      _react(true);
      setState(() {
        _cased[tok] = c;
        _pending = -1;
        if (_hintTok == tok) _hintTok = -1;
        _checkDone();
      });
    } else {
      _react(false);
      setState(() => _wrongCase = c);
      _wrongTimer?.cancel();
      _wrongTimer = Timer(Duration(milliseconds: appMotionOff(context) ? 150 : 720), () {
        if (mounted) setState(() => _wrongCase = -1);
      });
    }
  }

  void _checkDone() {
    if (_nextWord >= 0) return;
    _locked = true;
    _later(widget.advanceMs, _advance);
  }

  void _onTap(int tok) {
    if (_locked || _pending >= 0 || _placed.containsKey(tok)) return;
    setState(() => _sel = _sel == tok ? -1 : tok);
  }

  @override
  Widget build(BuildContext context) => StageFrame(
        session: s,
        kinds: kIrabHunter.kinds,
        silent: widget.silent,
        onHint: _hint,
        child: _body(context),
      );

  Widget _body(BuildContext context) {
    final theme = stageThemeOf(context, calm: s.calm);
    final sf = StageSurface(theme, context);
    final ms = appMotionOff(context) ? 0 : 340;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.content.max),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.sm),
            child: StageProgress(surface: sf, done: _done ? s.items.length : _i + (_locked ? 1 : 0), current: _i + 1, total: s.items.length),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: ms),
              switchInCurve: Curves.easeOutCubic,
              layoutBuilder: stageSwitcherLayout,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(anim), child: child),
              ),
              child: _done ? StageClosing(key: const ValueKey('done'), session: s, theme: theme, sf: sf) : _round(context, theme, sf),
            ),
          ),
        ]),
      ),
    );
  }

  // ── the sentence ────────────────────────────────────────────────────────────

  Widget _sentence(StageSurface sf, TextDirection dir, GameAge age) {
    final prompt = item.prompt.of(AppConfig.lang);
    final cell = <Widget>[];
    for (var k = 0; k < _r.words.length; k++) {
      final w = _r.words[k];
      final placed = _placed.containsKey(k);
      final focus = k == _pending;
      final label = placed
          ? (_cased.containsKey(k) ? '${_r.buckets[_placed[k]!]} · ${_r.cases[_cased[k]!]}' : _r.buckets[_placed[k]!])
          : '';
      cell.add(Container(
        key: ValueKey('word-$k'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
        decoration: BoxDecoration(
          color: focus ? sf.tint(sf.accent, 0.16) : placed ? sf.tint(sf.right, 0.14) : sf.tint(sf.ink, 0.05),
          borderRadius: BorderRadius.circular(sf.radius - 8),
          border: Border.all(color: focus ? sf.accent : placed ? sf.right.withValues(alpha: 0.6) : sf.edge, width: focus ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(w.text, textDirection: textDirectionOf(w.text, dir), style: appText(24, w: FontWeight.w700, c: sf.ink, h: 1.9)),
          SizedBox(
            height: 20,
            child: label.isEmpty
                ? null
                : Text(label, maxLines: 1, style: appText(12, w: FontWeight.w700, c: sf.ink.withValues(alpha: 0.7))),
          ),
        ]),
      ));
    }
    final text = Column(mainAxisSize: MainAxisSize.min, children: [
      if (prompt.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(prompt, textAlign: TextAlign.center, style: appText(17, w: FontWeight.w700, c: sf.ink, h: 1.45)),
        ),
      Directionality(
        textDirection: dir,
        child: Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: cell),
      ),
    ]);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: sf.paper, borderRadius: BorderRadius.circular(sf.radius + 4), boxShadow: sf.lift(blur: 24, dy: 10)),
      child: age == GameAge.kids && !sf.calm
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox.square(dimension: 56, child: GameCharacter(theme: sf.theme, mood: _mood, size: 56)),
              AppSpace.gapSm,
              Expanded(child: text),
            ])
          : text,
    );
  }

  // ── the case panel and the tap row ──────────────────────────────────────────

  /// Equal tiles in rows of at least 110 px each (never a lone orphan on a phone).
  Widget _grid(List<Widget> tiles) => LayoutBuilder(builder: (context, box) {
        const gap = AppSpace.sm;
        final cols = ((box.maxWidth + gap) / (110 + gap)).floor().clamp(1, tiles.length);
        final w = (box.maxWidth - (cols - 1) * gap) / cols;
        return Wrap(alignment: WrapAlignment.center, spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      });

  Widget _fit(String text, TextStyle style) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, textAlign: TextAlign.center, maxLines: 1, style: style));

  Widget _casePanel(StageSurface sf) {
    final w = _r.words[_pending];
    final right = _r.caseOf(_pending);
    return Container(
      key: const ValueKey('case-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: sf.tint(sf.accent, 0.1),
        borderRadius: BorderRadius.circular(sf.radius),
        border: Border.all(color: sf.accent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('ما حركة إعراب «${w.text}»؟', 'What is the case ending of «${w.text}»?'),
            textAlign: TextAlign.center, style: appText(17, w: FontWeight.w700, c: sf.ink, h: 1.8)),
        AppSpace.gapSm,
        _grid([
          for (var c = 0; c < _r.cases.length; c++)
            StageTile(
              key: ValueKey('case-$c'),
              surface: sf,
              state: c == _wrongCase
                  ? StageTileState.wrong
                  : (_hintTok == _pending && c == right)
                      ? StageTileState.hint
                      : StageTileState.idle,
              semanticsLabel: _r.cases[c],
              onTap: () => _pickCase(c),
              child: _fit(_r.cases[c], appText(17, w: FontWeight.w700, c: sf.ink, h: 1.6)),
            ),
        ]),
      ]),
    );
  }

  Widget _bucketRow(StageSurface sf) {
    final w = _r.words[_sel];
    return Container(
      key: const ValueKey('bucket-row'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: sf.tint(sf.gold, 0.2), borderRadius: BorderRadius.circular(sf.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('أين تضع «${w.text}»؟', 'Where does «${w.text}» go?'),
            textAlign: TextAlign.center, style: appText(16, w: FontWeight.w700, c: sf.ink, h: 1.8)),
        AppSpace.gapSm,
        _grid([
          for (var b = 0; b < _r.buckets.length; b++)
            StageTile(
              key: ValueKey('pick-$b'),
              surface: sf,
              semanticsLabel: _r.buckets[b],
              onTap: () => _drop(_sel, b),
              child: _fit(_r.buckets[b], appText(16, w: FontWeight.w700, c: sf.ink, h: 1.6)),
            ),
        ]),
      ]),
    );
  }

  // ── the round ───────────────────────────────────────────────────────────────

  Widget _round(BuildContext context, AgeTheme theme, StageSurface sf) {
    final r = _r;
    final dir = r.words.any((w) => isArabicText(w.text)) ? TextDirection.rtl : Directionality.of(context);
    final hintBucket = _hintTok >= 0 && _pending < 0 ? r.bucketOf(_hintTok) : -1;
    final slots = <DragSlotData>[
      for (var b = 0; b < r.buckets.length; b++)
        DragSlotData(
          id: b,
          label: r.buckets[b],
          capacity: r.words.length,
          state: b == _wrongSlot
              ? DragSlotState.wrong
              : b == hintBucket
                  ? DragSlotState.hint
                  : DragSlotState.open,
          tokens: [
            for (var k = 0; k < r.words.length; k++)
              if (_placed[k] == b || (b == _wrongSlot && k == _wrongTok)) DragToken(id: k, text: r.words[k].text),
          ],
        ),
    ];
    final tray = [
      for (final k in item.show)
        if (k >= 0 && k < r.words.length)
          DragToken(
            id: k,
            text: r.words[k].text,
            used: _placed.containsKey(k) || (k == _wrongTok && _wrongSlot >= 0),
            hint: k == _sel || (k == _hintTok && _pending < 0),
            image: null,
          ),
    ];
    return SingleChildScrollView(
      key: ValueKey('r$_i'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppReveal(index: 0, group: 'ih$_i', child: _sentence(sf, dir, theme.age)),
        AppSpace.gapMd,
        if (_pending >= 0) ...[_casePanel(sf), AppSpace.gapMd],
        if (_sel >= 0 && _pending < 0) ...[_bucketRow(sf), AppSpace.gapMd],
        AppReveal(
          index: 1,
          group: 'ib$_i',
          child: LayoutBuilder(builder: (context, box) => DragBoard(
            bucketColumns: box.maxWidth >= 640 ? r.buckets.length.clamp(2, 3) : 2,
            theme: theme,
            layout: DragBoardLayout.buckets,
            slots: slots,
            tray: tray,
            onDrop: _drop,
            onTapToken: _onTap,
            shakeSlot: _wrongSlot,
            shakeNonce: _shake,
            textDirection: dir,
            silent: widget.silent,
          )),
        ),
        AppSpace.gapMd,
      ]),
    );
  }
}
