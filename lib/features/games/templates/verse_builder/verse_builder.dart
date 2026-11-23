// lib/features/games/templates/verse_builder/verse_builder.dart — Verse Builder (Games v4 T37, CONTRACT §2): the
// reference template of DragBoard. `sequence` items in the modes `order` (put every word in its place) and `complete`
// (fill the missing words of an ayah / hadith / sentence), over a word, a letter, an ayah or a waqf segment.
//
//   - the recitation of the item plays FIRST, when the question appears (a Quran item carries `media.audio`); the
//     speaker button plays it again, and the reciter chip is the quick switch of CONTRACT §9 (the same ayah replays
//     with the new voice; the score and the trace do not change);
//   - drag a word to its place (it lifts, the place glows, it snaps in) or tap it (it goes to the next open place);
//   - a right word is locked in green; a wrong one shakes, flies back, and in a sacred round the AYAH REPLAYS so the
//     learner hears the right word and tries again (calm: amber, no shake, no red, nothing lost);
//   - only the first try of each place is reported (`s.answer(i, [slot, token])`): a retry is local;
//   - Quran text is drawn in the Quran role (stage_kit: quranTextStyle) on a tall line, so tashkeel never clips; Arabic
//     text lays out right to left whatever the app language is.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal, appMotionOff;
import 'package:flutter_education_app/features/games/bases/drag_board.dart';
import 'package:flutter_education_app/features/games/bases/question_stage.dart' show StageClosing;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';

class VerseBuilderTemplate extends GameTemplate {
  const VerseBuilderTemplate();

  @override
  String get key => 'verse_builder';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.sequence};
  @override
  Set<ItemType> get accepts => const {ItemType.sequence};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'بنّاء الآية';
  @override
  String get nameEn => 'Verse Builder';
  @override
  IconData get icon => Icons.view_week_rounded;

  @override
  Widget build(GameSession s) => VerseBuilderGame(session: s);
}

const VerseBuilderTemplate kVerseBuilder = VerseBuilderTemplate();

class VerseBuilderGame extends StatefulWidget {
  const VerseBuilderGame({super.key, required this.session, this.silent = false, this.reciters, this.advanceMs = 1100});
  final GameSession session;
  final bool silent;
  final ReciterLoader? reciters;
  final int advanceMs;

  @override
  State<VerseBuilderGame> createState() => _VerseBuilderGameState();
}

class _VerseBuilderGameState extends State<VerseBuilderGame> {
  int _i = 0;
  bool _done = false;

  // per item
  final Map<int, int> _placed = {}; // slot -> token
  final Set<int> _tried = {};
  int _wrongSlot = -1, _wrongTok = -1, _shake = 0;
  int _hintSlot = -1;
  bool _locked = false;
  Timer? _timer, _wrongTimer;

  GameSession get s => widget.session;
  GameItem get item => s.items[_i];
  bool get _calm => s.calm || s.sacred || item.sacred;

  List get _tokens => (item.body['tokens'] as List?) ?? const [];
  List get _extra => (item.body['extra'] as List?) ?? const [];
  int get _n => _tokens.length;
  Set<int> get _blanks => item.intList('blanks').toSet();
  String _text(int k) => k < _n ? '${_tokens[k]}' : '${_extra[k - _n]}';
  bool _right(int tok, int slot) {
    final eq = item.body['eq'] as List;
    return tok < _n && eq[tok] == eq[slot];
  }

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !s.finished) _play();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wrongTimer?.cancel();
    s.removeListener(_onSession);
    unawaited(GameAudio.instance.stopRecitation());
    super.dispose();
  }

  void _onSession() {
    if (s.finished && !_done && mounted) setState(() => _done = true);
  }

  void _play() {
    final segs = stageSegments(item);
    if (segs.isEmpty) return;
    final r = s.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(segs, reciter: r is String ? r : null).catchError((Object _) {}));
  }

  int get _nextSlot {
    for (var p = 0; p < _n; p++) {
      if (_blanks.contains(p) && !_placed.containsKey(p)) return p;
    }
    return -1;
  }

  void _later(int ms, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: appMotionOff(context) ? ms ~/ 4 : ms), () {
      if (mounted) f();
    });
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
      _placed.clear();
      _tried.clear();
      _wrongSlot = _wrongTok = -1;
      _hintSlot = -1;
      _locked = false;
    });
    _play();
  }

  void _hint() {
    if (_locked || _done || _hintSlot >= 0) return;
    final slot = _nextSlot;
    if (slot < 0) return;
    HapticFeedback.selectionClick();
    setState(() => _hintSlot = slot);
  }

  int? get _hintTok {
    if (_hintSlot < 0) return null;
    for (final k in item.show) {
      if (!_placed.containsValue(k) && _right(k, _hintSlot)) return k;
    }
    return null;
  }

  void _onTap(int tok) {
    final slot = _nextSlot;
    if (slot >= 0) _place(tok, slot);
  }

  void _place(int tok, int slot) {
    if (_locked || _done || !_blanks.contains(slot) || _placed.containsKey(slot) || _wrongSlot >= 0) return;
    final right = _right(tok, slot);
    if (_tried.add(slot)) s.answer(_i, [slot, tok], hint: _hintSlot == slot);
    if (right) {
      setState(() {
        _placed[slot] = tok;
        if (_hintSlot == slot) _hintSlot = -1;
        if (_nextSlot < 0) _locked = true;
      });
      HapticFeedback.mediumImpact();
      if (_locked) {
        if (item.sacred) _play();
        _later(item.sacred ? widget.advanceMs + 700 : widget.advanceMs, _advance);
      }
    } else {
      setState(() {
        _wrongSlot = slot;
        _wrongTok = tok;
        _shake++;
      });
      HapticFeedback.heavyImpact();
      // a sacred round: the ayah plays again so the right word is heard, then the learner tries again
      if (item.sacred || _calm) _play();
      _wrongTimer?.cancel();
      _wrongTimer = Timer(Duration(milliseconds: appMotionOff(context) ? 150 : 720), () {
        if (mounted) setState(() => _wrongSlot = _wrongTok = -1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StageFrame(
      session: s,
      kinds: kVerseBuilder.kinds,
      silent: widget.silent,
      onHint: _hint,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final theme = stageThemeOf(context, calm: s.calm || s.sacred);
    final sf = StageSurface(theme, context);
    final ms = appMotionOff(context) ? 0 : 340;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
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
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _done ? StageClosing(key: const ValueKey('done'), session: s, theme: theme, sf: sf) : _round(context, theme, sf),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _round(BuildContext context, AgeTheme theme, StageSurface sf) {
    final it = item;
    final quran = it.sourceKind == 'quran';
    final audio = it.media.audio != null && it.media.audio!.isNotEmpty;
    final prompt = it.prompt.of(AppConfig.lang);
    final label = it.sourceLabel.of(AppConfig.lang);
    final sample = _tokens.isEmpty ? '' : '${_tokens.first}';
    final dir = textDirectionOf(sample, Directionality.of(context));
    final slots = <DragSlotData>[];
    for (var p = 0; p < _n; p++) {
      if (!_blanks.contains(p)) {
        slots.add(DragSlotData(id: p, state: DragSlotState.fixed, tokens: [DragToken(id: p, text: '${_tokens[p]}', quran: quran)]));
      } else if (_placed.containsKey(p)) {
        final k = _placed[p]!;
        slots.add(DragSlotData(id: p, state: DragSlotState.correct, number: p + 1, tokens: [DragToken(id: k, text: _text(k), quran: quran)]));
      } else if (p == _wrongSlot) {
        slots.add(DragSlotData(id: p, state: DragSlotState.wrong, number: p + 1, tokens: [DragToken(id: _wrongTok, text: _text(_wrongTok), quran: quran)]));
      } else {
        slots.add(DragSlotData(id: p, number: p + 1, state: p == _hintSlot ? DragSlotState.hint : DragSlotState.open));
      }
    }
    final hintTok = _hintTok;
    final tray = [
      for (final k in it.show)
        DragToken(
          id: k,
          text: _text(k),
          quran: quran,
          used: _placed.containsValue(k) || (k == _wrongTok && _wrongSlot >= 0),
          hint: k == hintTok,
        ),
    ];
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: sf.paper,
        borderRadius: BorderRadius.circular(sf.radius + AppSpace.xxs),
        boxShadow: sf.lift(blur: 24, dy: 10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
            decoration: BoxDecoration(color: sf.tint(sf.gold, 0.25), borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Text(label, style: appText(13, w: FontWeight.w700, c: sf.ink), textDirection: textDirectionOf(label, Directionality.of(context))),
          ),
        if (label.isNotEmpty) AppSpace.gapSm,
        if (prompt.isNotEmpty)
          Text(prompt, textAlign: TextAlign.center, style: appText(19, w: FontWeight.w700, c: sf.ink, h: 1.45)),
        if (audio) ...[
          AppSpace.gapSm,
          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            StageListenButton(surface: sf, onPressed: _play),
            StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: s.reciter?['key'] as String?),
          ]),
        ],
      ]),
    );
    return SingleChildScrollView(
      key: ValueKey('r$_i'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppReveal(index: 0, group: 'vp$_i', child: card),
        AppSpace.gapLg,
        AppReveal(
          index: 1,
          group: 'vb$_i',
          child: DragBoard(
            theme: theme,
            slots: slots,
            tray: tray,
            onDrop: (tok, slot) => _place(tok, slot),
            onTapToken: _onTap,
            shakeSlot: _wrongSlot,
            shakeNonce: _shake,
            textDirection: dir,
            silent: widget.silent,
          ),
        ),
        AppSpace.gapMd,
      ]),
    );
  }
}
