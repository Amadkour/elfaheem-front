// lib/features/games/bases/question_stage.dart — the QuestionStage base of Games v4 (T37): one question at a time,
// answered by tapping. It plays `mcq`, `true_false`, `select_all` and, as "pick the next / missing word",
// `sequence` in the modes `next_word`, `complete` and `order` (one pick per blank, the way Growing Tree plays it).
// Templates (Challenge Quiz, Map Adventure, Growing Tree) put their own look around it through [header].
//
//   - reports every FIRST try to the session (`s.answer(i, a, hint:)`, CONTRACT §5); a retry is local and never
//     reported, so the score, the trace and the live effects (GameFxSession) stay exact;
//   - a wrong answer: the tile shakes and goes red (the right one lights up) and the round moves on; in a calm round
//     (sacred text: `session.calm` / `sacred`) it goes a soft amber, `onWrong` fires (a Quran template replays the
//     ayah) and the learner tries again, nothing is lost;
//   - a hint (the shell's lamp, through [QuestionStageController.hint]) dims one wrong option, or lights the right
//     token of a sequence; the next report carries `h: true`;
//   - the end of the last question finishes the session (`done`); a session ended from outside (timer, lives, quit)
//     shows the closing card too.
//
// It reads the age theme from AgeThemeScope (turned calm for sacred text) and draws its tiles with stage_kit.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal, appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

import 'stage_kit.dart';

/// Lets the template's shell ask the stage for a hint.
class QuestionStageController {
  VoidCallback? _hint;

  /// True when a hint can still be given on the current question.
  bool get canHint => _canHint?.call() ?? false;
  bool Function()? _canHint;

  void hint() => _hint?.call();
}

typedef StageHeaderBuilder = Widget? Function(BuildContext context, GameItem item, StageSurface surface);

class QuestionStage extends StatefulWidget {
  const QuestionStage({
    super.key,
    required this.session,
    this.controller,
    this.header,
    this.onItemShown,
    this.onWrong,
    this.onRight,
    this.silent = false,
    this.advanceMs = 1100,
  });

  final GameSession session;
  final QuestionStageController? controller;

  /// A widget drawn above the question card (a template's character, a map strip, the reciter switch).
  final StageHeaderBuilder? header;

  /// A question appeared (also the first one). A Quran template starts the recitation here.
  final void Function(GameItem item)? onItemShown;

  /// A first or later wrong try on [item].
  final void Function(GameItem item)? onWrong;

  /// A right answer (the unit is done).
  final void Function(GameItem item)? onRight;
  final bool silent;

  /// How long a finished question stays before the next one slides in.
  final int advanceMs;

  @override
  State<QuestionStage> createState() => _QuestionStageState();
}

class _QuestionStageState extends State<QuestionStage> {
  int _i = 0;
  bool _done = false;

  // per question
  final Map<int, StageTileState> _st = {};
  final Map<int, int> _bump = {}, _shake = {};
  final Set<int> _picked = {}, _used = {};
  final Set<String> _reported = {};
  final Map<int, int> _filled = {};
  bool _locked = false, _hinted = false;
  int _hintSlot = -1;
  Timer? _timer;
  bool _explain = false;

  GameSession get s => widget.session;
  GameItem get item => s.items[_i];
  bool get _calm => s.calm || s.sacred || item.sacred;

  @override
  void initState() {
    super.initState();
    widget.controller?._hint = _hint;
    widget.controller?._canHint = () => !_locked && !_done && !_hinted && _hintSlot < 0;
    s.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !s.finished) widget.onItemShown?.call(item);
    });
  }

  @override
  void didUpdateWidget(QuestionStage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      widget.controller?._hint = _hint;
      widget.controller?._canHint = () => !_locked && !_done && !_hinted && _hintSlot < 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (s.finished && !_done && mounted) setState(() => _done = true);
  }

  // ---- the question's data ----

  List<int> get _order => item.type == ItemType.trueFalse ? const [1, 0] : item.show;

  List get _tokens => (item.body['tokens'] as List?) ?? const [];
  List get _extra => (item.body['extra'] as List?) ?? const [];
  int get _n => _tokens.length;
  bool get _isSeq => item.type == ItemType.sequence;

  String _label(int k) {
    switch (item.type) {
      case ItemType.trueFalse:
        return k == 1 ? t('صحيح', 'True') : t('خطأ', 'False');
      case ItemType.sequence:
        return k < _n ? '${_tokens[k]}' : '${_extra[k - _n]}';
      default:
        final o = (item.body['options'] as List)[k];
        return stageText(o is Map ? o['text'] : o);
    }
  }

  /// The picture of an `mcq` / `select_all` option (`options[k].image`), or null.
  String? _optionImage(int k) {
    if (item.type != ItemType.mcq && item.type != ItemType.selectAll) return null;
    final o = (item.body['options'] as List)[k];
    final u = o is Map ? o['image'] : null;
    return u is String && u.isNotEmpty ? u : null;
  }

  bool _isRight(int k) {
    switch (item.type) {
      case ItemType.mcq:
        return k == item.body['answer'];
      case ItemType.trueFalse:
        return (k == 1) == (item.body['answer'] == true);
      case ItemType.selectAll:
        return item.intList('answers').contains(k);
      default:
        return false;
    }
  }

  int get _slot {
    for (final b in item.intList('blanks')) {
      if (!_filled.containsKey(b)) return b;
    }
    return -1;
  }

  bool _seqRight(int tok, int slot) {
    final eq = item.body['eq'] as List;
    return tok < _n && eq[tok] == eq[slot];
  }

  // ---- flow ----

  void _reset() {
    _st.clear();
    _bump.clear();
    _shake.clear();
    _picked.clear();
    _used.clear();
    _reported.clear();
    _filled.clear();
    _locked = false;
    _hinted = false;
    _hintSlot = -1;
    _explain = false;
  }

  void _later(int ms, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: appMotionOff(context) ? (ms ~/ 4) : ms), () {
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
      _reset();
    });
    widget.onItemShown?.call(item);
  }

  void _ring(bool right) {
    HapticFeedback.mediumImpact();
    if (right) {
      widget.onRight?.call(item);
    } else {
      widget.onWrong?.call(item);
    }
  }

  void _hint() {
    if (_locked || _done || _hinted || _hintSlot >= 0) return;
    setState(() {
      switch (item.type) {
        case ItemType.sequence:
          final slot = _slot;
          if (slot < 0) return;
          _hintSlot = slot;
          for (final k in _order) {
            if (!_used.contains(k) && _seqRight(k, slot)) {
              _st[k] = StageTileState.hint;
              _bump[k] = (_bump[k] ?? 0) + 1;
              break;
            }
          }
        default:
          // dim one wrong option
          for (final k in _order) {
            if (!_isRight(k) && !_st.containsKey(k)) {
              _st[k] = StageTileState.dim;
              break;
            }
          }
          _hinted = true;
      }
    });
    HapticFeedback.selectionClick();
  }

  void _onChoose(int k) {
    if (_locked || _done || _st[k] == StageTileState.dim) return;
    stageTick(sacred: _calm, silent: widget.silent);
    switch (item.type) {
      case ItemType.selectAll:
        setState(() {
          if (!_picked.remove(k)) _picked.add(k);
          _st[k] = _picked.contains(k) ? StageTileState.selected : StageTileState.idle;
          if (!_picked.contains(k)) _st.remove(k);
        });
      case ItemType.sequence:
        _onToken(k);
      default:
        _onSingle(k);
    }
  }

  void _onSingle(int k) {
    final right = _isRight(k);
    if (_reported.add('item')) s.answer(_i, k, hint: _hinted);
    setState(() {
      if (right) {
        _st[k] = StageTileState.correct;
        _bump[k] = (_bump[k] ?? 0) + 1;
        _locked = true;
        _explain = true;
      } else if (_calm) {
        _st[k] = StageTileState.wrong;
      } else {
        _st[k] = StageTileState.wrong;
        _shake[k] = (_shake[k] ?? 0) + 1;
        for (final o in _order) {
          if (_isRight(o)) _st[o] = StageTileState.correct;
        }
        _locked = true;
        _explain = true;
      }
    });
    _ring(right);
    if (_locked) _later(right ? widget.advanceMs : widget.advanceMs + 600, _advance);
  }

  void _check() {
    if (_locked || _done || _picked.isEmpty) return;
    final answers = item.intList('answers').toSet();
    final sorted = (_picked.toList()..sort());
    if (_reported.add('item')) s.answer(_i, sorted, hint: _hinted);
    final hits = _picked.intersection(answers);
    final perfect = hits.length == answers.length && _picked.length == answers.length;
    setState(() {
      for (final k in _picked) {
        _st[k] = answers.contains(k) ? StageTileState.correct : StageTileState.wrong;
        if (answers.contains(k)) {
          _bump[k] = (_bump[k] ?? 0) + 1;
        } else if (!_calm) {
          _shake[k] = (_shake[k] ?? 0) + 1;
        }
      }
      if (perfect || !_calm) {
        for (final a in answers) {
          if (!_picked.contains(a)) _st[a] = StageTileState.hint;
        }
        _locked = true;
        _explain = true;
      }
    });
    _ring(perfect);
    if (_locked) {
      _later(perfect ? widget.advanceMs + 200 : widget.advanceMs + 900, _advance);
    } else {
      // calm: the picks reset and the learner tries again
      _later(900, () => setState(() {
            _picked.clear();
            _st.removeWhere((_, v) => v != StageTileState.dim);
          }));
    }
  }

  void _onToken(int tok) {
    final slot = _slot;
    if (slot < 0 || _used.contains(tok)) return;
    final right = _seqRight(tok, slot);
    if (_reported.add('slot$slot')) s.answer(_i, [slot, tok], hint: _hintSlot == slot);
    setState(() {
      if (right) {
        _filled[slot] = tok;
        _used.add(tok);
        _st
          ..removeWhere((_, v) => v == StageTileState.hint)
          ..[tok] = StageTileState.correct;
        _bump[tok] = (_bump[tok] ?? 0) + 1;
        _hintSlot = -1;
        if (_slot < 0) {
          _locked = true;
          _explain = true;
        }
      } else {
        _st[tok] = StageTileState.wrong;
        if (!_calm) _shake[tok] = (_shake[tok] ?? 0) + 1;
      }
    });
    _ring(right);
    if (!right) {
      _later(700, () => setState(() {
            if (_st[tok] == StageTileState.wrong) _st.remove(tok);
          }));
    } else if (_locked) {
      _later(widget.advanceMs, _advance);
    }
  }

  // ---- drawing ----

  @override
  Widget build(BuildContext context) {
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
              child: _done ? StageClosing(key: const ValueKey('done'), session: s, theme: theme, sf: sf) : _question(context, sf),
            ),
          ),
          if (!_done && item.type == ItemType.selectAll) _checkBar(sf),
        ]),
      ),
    );
  }

  Widget _checkBar(StageSurface sf) {
    final can = !_locked && _picked.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
      child: SizedBox(
        width: double.infinity,
        height: AppTouch.primary,
        child: FilledButton(
          key: const ValueKey('check'),
          style: FilledButton.styleFrom(
            backgroundColor: sf.accent,
            foregroundColor: sf.paper,
            disabledBackgroundColor: sf.tint(sf.ink, 0.12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sf.radius)),
          ),
          onPressed: can ? _check : null,
          child: Text(t('تحقّق', 'Check'), style: appText(17, w: FontWeight.w700, c: can ? sf.paper : sf.ink.withValues(alpha: 0.5))),
        ),
      ),
    );
  }

  Widget _question(BuildContext context, StageSurface sf) {
    final it = item;
    final promptText = it.prompt.of(AppConfig.lang);
    final audio = it.media.audio != null && it.media.audio!.isNotEmpty;
    final hdr = widget.header?.call(context, it, sf);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: sf.paper,
        borderRadius: BorderRadius.circular(sf.radius + 4),
        boxShadow: sf.lift(blur: 24, dy: 10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if ((it.media.image ?? '').isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(sf.radius - 4),
            child: AppNetworkImage(url: it.media.image!, width: 200, height: 120, fit: BoxFit.cover),
          ),
          AppSpace.gapMd,
        ],
        if (promptText.isNotEmpty)
          Text(promptText,
              textAlign: TextAlign.center,
              style: appText(21, w: FontWeight.w700, c: sf.ink, h: 1.45),
              textDirection: textDirectionOf(promptText, Directionality.of(context))),
        if (_isSeq) ...[
          if (promptText.isNotEmpty) AppSpace.gapMd,
          _sentence(sf),
        ],
        if (audio) ...[
          AppSpace.gapMd,
          StageListenButton(surface: sf, onPressed: () => widget.onItemShown?.call(it)),
        ],
        if (_explain && it.explain.of(AppConfig.lang).isNotEmpty) ...[
          AppSpace.gapMd,
          AppReveal(
            index: 0,
            group: 'x$_i',
            child: Text(it.explain.of(AppConfig.lang),
                textAlign: TextAlign.center, style: appText(15, c: sf.ink.withValues(alpha: 0.75), h: 1.5)),
          ),
        ],
      ]),
    );
    return SingleChildScrollView(
      key: ValueKey('q$_i'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hdr != null) ...[hdr, AppSpace.gapMd],
        AppReveal(index: 0, group: 'p$_i', child: card),
        AppSpace.gapLg,
        _options(sf),
        AppSpace.gapMd,
      ]),
    );
  }

  Widget _sentence(StageSurface sf) {
    final quran = item.sourceKind == 'quran';
    final blanks = item.intList('blanks').toSet();
    final cur = _slot;
    final first = _n > 0 ? '${_tokens.first}' : '';
    final chips = <Widget>[];
    for (var p = 0; p < _n; p++) {
      final String text;
      StageTileState st = StageTileState.idle;
      var open = false;
      if (!blanks.contains(p)) {
        text = '${_tokens[p]}';
      } else if (_filled.containsKey(p)) {
        text = _label(_filled[p]!);
        st = StageTileState.correct;
      } else {
        text = '';
        open = true;
      }
      chips.add(_SentenceChip(
        key: ValueKey('s$p-${open ? 'o' : 'c'}'),
        sf: sf,
        text: text,
        quran: quran,
        open: open,
        active: open && p == cur,
        state: st,
      ));
    }
    return Directionality(
      textDirection: textDirectionOf(first, Directionality.of(context)),
      child: Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: chips),
    );
  }

  Widget _options(StageSurface sf) {
    final order = _order;
    final quran = item.sourceKind == 'quran';
    final twoUp = item.type == ItemType.trueFalse;
    Widget tile(int idx, int k) {
      final label = _label(k);
      final st = _st[k] ?? (_picked.contains(k) ? StageTileState.selected : StageTileState.idle);
      if (_isSeq && _used.contains(k)) {
        return const SizedBox.shrink();
      }
      final arabicQuran = quran && isArabicText(label);
      final badge = (item.type == ItemType.mcq || item.type == ItemType.selectAll) ? _badge(idx) : null;
      return AppReveal(
        index: idx + 1,
        group: 'o$_i',
        child: StageReact(
          key: ValueKey('opt-$k'),
          bump: _bump[k] ?? 0,
          shake: _shake[k] ?? 0,
          child: StageTile(
            surface: sf,
            state: st,
            expand: !_isSeq,
            badge: badge,
            semanticsLabel: label,
            onTap: _locked ? null : () => _onChoose(k),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_optionImage(k) != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(10), child: AppNetworkImage(url: _optionImage(k)!, width: 48, height: 48, fit: BoxFit.cover)),
                AppSpace.gapSm,
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  textDirection: textDirectionOf(label, Directionality.of(context)),
                  style: arabicQuran ? quranTextStyle(19, color: sf.ink) : appText(18, w: FontWeight.w600, c: sf.ink, h: 1.3),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 560 && order.length >= 4 && !_isSeq;
      if (twoUp || wide || (_isSeq && box.maxWidth >= 420)) {
        final cols = twoUp ? 2 : (_isSeq ? 3 : 2);
        const gap = AppSpace.sm;
        if (_isSeq) {
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: gap,
            runSpacing: AppSpace.xs,
            children: [for (var j = 0; j < order.length; j++) tile(j, order[j])],
          );
        }
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (var j = 0; j < order.length; j++) SizedBox(width: w, child: tile(j, order[j]))],
        );
      }
      if (_isSeq) {
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [for (var j = 0; j < order.length; j++) tile(j, order[j])],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < order.length; j++) ...[
            tile(j, order[j]),
            if (j < order.length - 1) AppSpace.gapSm,
          ],
        ],
      );
    });
  }

  String _badge(int j) => AppConfig.lang == 'ar' ? const ['أ', 'ب', 'ج', 'د', 'هـ', 'و', 'ز', 'ح'][j.clamp(0, 7)] : String.fromCharCode(65 + j);
}

/// One word of the sentence of a sequence question: a plain token, a filled one, or an open blank.
class _SentenceChip extends StatelessWidget {
  const _SentenceChip({super.key, required this.sf, required this.text, required this.quran, required this.open, required this.active, required this.state});
  final StageSurface sf;
  final String text;
  final bool quran, open, active;
  final StageTileState state;

  @override
  Widget build(BuildContext context) {
    final color = state == StageTileState.correct ? sf.right : sf.ink;
    final style = quran && isArabicText(text) ? quranTextStyle(22, color: color) : appText(20, w: FontWeight.w700, c: color);
    if (open) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 48,
        decoration: BoxDecoration(
          color: active ? sf.tint(sf.accent, 0.14) : sf.tint(sf.ink, 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? sf.accent : sf.edge, width: active ? 2.5 : 1.5),
        ),
      );
    }
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      decoration: state == StageTileState.correct
          ? BoxDecoration(color: sf.tint(sf.right, 0.18), borderRadius: BorderRadius.circular(12))
          : null,
      child: Text(text, style: style, textDirection: textDirectionOf(text)),
    );
    if (state != StageTileState.correct || appMotionOff(context)) return chip;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.7, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (_, v, c) => Transform.scale(scale: v, child: c),
      child: chip,
    );
  }
}

/// The closing card: the character cheers (or consoles) while the page takes over.
class StageClosing extends StatelessWidget {
  const StageClosing({super.key, required this.session, required this.theme, required this.sf});
  final GameSession session;
  final AgeTheme theme;
  final StageSurface sf;

  @override
  Widget build(BuildContext context) {
    final good = session.score * 2 >= session.maxScore;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(dimension: 160, child: GameCharacter(theme: theme, mood: good ? GameMood.happy : GameMood.sad, size: 160)),
        AppSpace.gapSm,
        Text(good ? t('أحسنت!', 'Well done!') : t('انتهت الجولة', 'Round over'),
            style: appText(24, w: FontWeight.w800, c: sf.ink)),
      ]),
    );
  }
}
