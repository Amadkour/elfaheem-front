// lib/features/games/templates/science_lab/science_lab.dart — Science Lab (Games v4 T54, CONTRACT §2): `combine` items (drag
// the ingredient jars into the flask, press Mix, and the right set reacts: fizz / colour / freeze / glow / smoke by the
// item's `fx`) and `mcq` items (the cause-and-effect question after it). Never sacred.
//
//   - tap a jar, then tap the flask (the same board works with a mouse, a keyboard, a screen reader: no drag needed);
//   - Mix reports the picked ingredient indices ONCE (`s.answer(i, [k…])`, the first try); a wrong mix fizzles out and
//     the flask empties, you try again (nothing more is reported); a right one plays the reaction and the result line;
//   - Empty tips the flask out; the hint lights one missing ingredient;
//   - an `mcq` is plain tiles under the same character; the first tap is the one reported.
// The scene is the flask: its liquid rises with every jar, and the reaction is the reward of a right mix.
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
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/templates/science_lab/lab_art.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

class ScienceLabTemplate extends GameTemplate {
  const ScienceLabTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => 'science_lab';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.combine, MechanicKind.choose};
  @override
  Set<ItemType> get accepts => const {ItemType.combine, ItemType.mcq};
  @override
  bool get sacredAllowed => false;
  @override
  String get nameAr => 'مختبر العلوم';
  @override
  String get nameEn => 'Science Lab';
  @override
  IconData get icon => Icons.science_rounded;

  @override
  Widget build(GameSession s) => ScienceLabGame(session: s, silent: silent);
}

const ScienceLabTemplate kScienceLab = ScienceLabTemplate();

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _defaultPicture(BuildContext context, String url, double size) => AppNetworkImage(url: url, width: size, height: size, fit: BoxFit.cover);

class ScienceLabGame extends StatefulWidget {
  const ScienceLabGame({super.key, required this.session, this.silent = false, this.advanceMs = 2600, this.imageBuilder});
  final GameSession session;
  final bool silent;

  /// How long a right mix stays on screen (the reaction plays, then the result line) before the next item.
  final int advanceMs;

  /// Test hook: how pictures are drawn (null = the app's network image).
  final DragImageBuilder? imageBuilder;

  @override
  State<ScienceLabGame> createState() => _ScienceLabGameState();
}

class _ScienceLabGameState extends State<ScienceLabGame> {
  int _i = 0;
  bool _done = false;

  // per combine item
  final List<int> _picked = [];
  int _sel = -1, _hintTok = -1, _shake = 0, _nonce = 0;
  String? _fx;
  bool _wrongMix = false;

  // per mcq item
  final Map<int, StageTileState> _st = {};
  final Map<int, int> _bump = {}, _shakeOpt = {};
  bool _showExplain = false;

  // both
  bool _reported = false, _hinted = false, _locked = false;
  GameMood _mood = GameMood.idle;
  Timer? _timer, _wrongTimer, _moodTimer;

  GameSession get s => widget.session;
  GameItem get item => s.items[_i];
  bool get _isCombine => item.type == ItemType.combine;

  List get _ings => (item.body['ingredients'] as List?) ?? const [];
  List<String> get _answerKeys => [for (final v in (item.body['answer'] as List? ?? const [])) '$v'];
  String _key(int k) => '${(_ings[k] as Map)['key']}';
  String _label(int k) {
    final l = (_ings[k] as Map)['label'];
    return l is Map ? GameText.from(l).of(AppConfig.lang) : '${l ?? _key(k)}';
  }

  String? _image(int k) {
    final v = (_ings[k] as Map)['image'];
    return v is String && v.isNotEmpty ? v : null;
  }

  List<int> _order() {
    final l = item.body['show'];
    return l is List && l.length == _ings.length ? [for (final v in l) (v as num).toInt()] : [for (var k = 0; k < _ings.length; k++) k];
  }

  bool _skip(GameItem it) => it.sacred || (it.type != ItemType.combine && it.type != ItemType.mcq);

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    while (_i < s.items.length && _skip(s.items[_i])) {
      _i++;
    }
    if (_i >= s.items.length) {
      _i = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !s.finished) {
          setState(() => _done = true);
          s.finish('done');
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wrongTimer?.cancel();
    _moodTimer?.cancel();
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

  void _setMood(GameMood m) {
    _mood = m;
    _moodTimer?.cancel();
    _moodTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _mood = GameMood.idle);
    });
  }

  void _advance() {
    if (s.finished) {
      setState(() => _done = true);
      return;
    }
    var next = _i + 1;
    while (next < s.items.length && _skip(s.items[next])) {
      next++;
    }
    if (next >= s.items.length) {
      setState(() => _done = true);
      s.finish('done');
      return;
    }
    setState(() {
      _i = next;
      _picked.clear();
      _sel = _hintTok = -1;
      _fx = null;
      _wrongMix = false;
      _st.clear();
      _bump.clear();
      _shakeOpt.clear();
      _showExplain = false;
      _reported = _hinted = _locked = false;
      _mood = GameMood.idle;
    });
  }

  // ── combine ──

  void _pour(int k) {
    if (_locked || _done || _wrongMix || _picked.contains(k)) return;
    HapticFeedback.selectionClick();
    stageTick(silent: widget.silent);
    setState(() {
      _picked.add(k);
      _sel = -1;
      if (_hintTok == k) _hintTok = -1;
    });
  }

  void _onDrop(int tok, int slot) => _pour(tok);

  /// A tap on a jar picks it (again = puts it down); a tap on the flask then pours it in.
  void _onTapJar(int k) {
    if (_locked || _wrongMix || _picked.contains(k)) return;
    setState(() => _sel = _sel == k ? -1 : k);
  }

  void _onTapFlask(int slot) {
    if (_sel >= 0) _pour(_sel);
  }

  void _empty() {
    if (_locked || _wrongMix || _picked.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _picked.clear());
  }

  void _hint() {
    if (_locked || _done || !_isCombine || _hintTok >= 0) return;
    final keys = _answerKeys;
    for (final k in _order()) {
      if (keys.contains(_key(k)) && !_picked.contains(k)) {
        HapticFeedback.selectionClick();
        setState(() {
          _hintTok = k;
          _hinted = true;
        });
        return;
      }
    }
  }

  bool get _mixRight {
    final keys = _answerKeys.toSet();
    final got = {for (final k in _picked) _key(k)};
    return got.length == keys.length && got.containsAll(keys);
  }

  void _mix() {
    if (_locked || _done || _wrongMix || _picked.isEmpty) return;
    if (!_reported) {
      _reported = true;
      s.answer(_i, List<int>.of(_picked), hint: _hinted);
    }
    if (_mixRight) {
      HapticFeedback.mediumImpact();
      final fx = '${item.body['fx']}';
      setState(() {
        _locked = true;
        _fx = kLabFx.contains(fx) ? fx : 'fizz';
        _nonce++;
        _hintTok = -1;
        _setMood(GameMood.happy);
      });
      _later(widget.advanceMs, _advance);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _wrongMix = true;
        _fx = 'fail';
        _nonce++;
        _shake++;
        _setMood(GameMood.sad);
      });
      _wrongTimer?.cancel();
      _wrongTimer = Timer(Duration(milliseconds: appMotionOff(context) ? 200 : 1300), () {
        if (mounted) {
          setState(() {
            _wrongMix = false;
            _fx = null;
            _picked.clear();
          });
        }
      });
    }
  }

  // ── mcq ──

  void _choose(int k) {
    if (_locked || _done || _st[k] == StageTileState.wrong || _st[k] == StageTileState.dim) return;
    if (!_reported) {
      _reported = true;
      s.answer(_i, k, hint: _hinted);
    }
    final right = item.body['answer'] == k;
    HapticFeedback.mediumImpact();
    setState(() {
      if (right) {
        _locked = true;
        _st[k] = StageTileState.correct;
        _bump[k] = (_bump[k] ?? 0) + 1;
        _showExplain = true;
        _setMood(GameMood.happy);
      } else {
        _st[k] = StageTileState.wrong;
        _shakeOpt[k] = (_shakeOpt[k] ?? 0) + 1;
        _setMood(GameMood.sad);
      }
    });
    if (right) _later(1300, _advance);
  }

  void _hintMcq() {
    if (_locked || _done || _hinted) return;
    final right = item.body['answer'];
    for (final k in item.show) {
      if (k != right && _st[k] == null) {
        setState(() {
          _st[k] = StageTileState.dim;
          _hinted = true;
        });
        return;
      }
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return StageFrame(
      fxUnder: true,
      session: s,
      kinds: kScienceLab.kinds,
      silent: widget.silent,
      onHint: () => _isCombine ? _hint() : _hintMcq(),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final theme = stageThemeOf(context, calm: s.calm);
    final sf = StageSurface(theme, context);
    final ms = appMotionOff(context) ? 0 : 340;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (wide ? AppWidth.wide : AppWidth.reading).max),
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
              child: _done ? StageClosing(key: const ValueKey('done'), session: s, theme: theme, sf: sf) : _round(context, theme, sf, wide),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _head(AgeTheme theme, StageSurface sf, {required bool column}) {
    final prompt = item.prompt.of(AppConfig.lang);
    final char = GameCharacter(theme: theme, equipped: const {'hat': 'hat_goggles'}, mood: _mood, size: column ? 120 : 92);
    final card = Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: sf.paper, borderRadius: BorderRadius.circular(sf.radius + 4), boxShadow: sf.lift(blur: 24, dy: 10)),
      child: Text(prompt, textAlign: column ? TextAlign.center : TextAlign.start, style: appText(19, w: FontWeight.w700, c: sf.ink, h: 1.45)),
    );
    if (column) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: char), AppSpace.gapSm, card]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [char, AppSpace.gapSm, Expanded(child: card)]);
  }

  Widget _round(BuildContext context, AgeTheme theme, StageSurface sf, bool wide) {
    final Widget content;
    if (_isCombine) {
      final lab = _lab(context, theme, sf, wide);
      content = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: AppReveal(index: 0, group: 'sl$_i', child: _head(theme, sf, column: true))),
              AppSpace.gapLg,
              Expanded(flex: 3, child: lab),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [AppReveal(index: 0, group: 'sl$_i', child: _head(theme, sf, column: false)), AppSpace.gapMd, lab]);
    } else {
      content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppReveal(index: 0, group: 'sl$_i', child: _head(theme, sf, column: false)),
        AppSpace.gapLg,
        _options(sf),
        if (_showExplain && item.explain.of(AppConfig.lang).isNotEmpty) ...[
          AppSpace.gapMd,
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(color: sf.tint(sf.right, 0.18), borderRadius: BorderRadius.circular(sf.radius), border: Border.all(color: sf.right.withValues(alpha: .6))),
            child: Text(item.explain.of(AppConfig.lang), style: appText(16, w: FontWeight.w600, c: sf.ink, h: 1.45)),
          ),
        ],
      ]);
    }
    return SingleChildScrollView(
      key: ValueKey('r$_i'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(children: [content, AppSpace.gapMd]),
    );
  }

  // ── the lab (combine) ──

  Color _liquid(StageSurface sf) {
    Color? c;
    for (final k in _picked) {
      final jc = labJarColor(sf.p, sf.right, _key(k));
      c = c == null ? jc : Color.lerp(c, jc, .5)!;
    }
    return c ?? sf.p.accent;
  }

  Widget _lab(BuildContext context, AgeTheme theme, StageSurface sf, bool wide) {
    final n = _ings.length;
    final level = _picked.isEmpty ? 0.0 : 0.18 + 0.5 * (_picked.length / (n == 0 ? 1 : n));
    final liquid = _liquid(sf);
    final pic = widget.imageBuilder ?? _defaultPicture;
    final result = GameText.from(item.body['result']).of(AppConfig.lang);
    final tray = [
      for (final k in _order()) DragToken(id: k, text: _label(k), image: _image(k), used: _picked.contains(k), hint: k == _hintTok || k == _sel),
    ];
    final flask = DragSlotData(
      id: 0,
      label: _t('الدورق', 'Flask'),
      capacity: n,
      state: _locked ? DragSlotState.correct : (_wrongMix ? DragSlotState.wrong : DragSlotState.open),
      tokens: [for (final k in _picked) DragToken(id: k, text: _label(k))],
    );
    final board = DragBoard(
      theme: theme,
      layout: DragBoardLayout.buckets,
      bucketColumns: 1,
      imageBuilder: widget.imageBuilder,
      slots: [flask],
      tray: tray,
      onDrop: _onDrop,
      onTapToken: _onTapJar,
      onTapSlot: _onTapFlask,
      shakeSlot: _wrongMix ? 0 : -1,
      shakeNonce: _shake,
      silent: widget.silent,
      slotBuilder: (context, slot, hover) => LayoutBuilder(builder: (context, box) {
        final h = (box.maxWidth * (wide ? .42 : .46)).clamp(140.0, wide ? 250.0 : 176.0);
        return Semantics(
          label: _t('الدورق: ${_picked.length} مكونات', 'Flask: ${_picked.length} ingredients'),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: LabFlask(
                key: const ValueKey('lab-flask'),
                palette: sf.p,
                level: level,
                liquid: liquid,
                fx: _fx,
                nonce: _nonce,
                hover: hover,
                wrong: _wrongMix && !sf.calm,
                thick: theme.outline,
                height: h,
              ),
            ),
            AppSpace.gapXs,
            SizedBox(
              height: 34,
              child: Center(
                child: _picked.isEmpty
                    ? Text(_t('اسحب المكونات إلى الدورق', 'Drag ingredients into the flask'), textAlign: TextAlign.center, style: appText(14, w: FontWeight.w600, c: sf.onSky))
                    : Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, children: [
                        for (final k in _picked)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                            decoration: BoxDecoration(color: sf.tint(labJarColor(sf.p, sf.right, _key(k)), .3), borderRadius: BorderRadius.circular(AppRadius.pill)),
                            child: Text(_label(k), style: appText(13, w: FontWeight.w700, c: sf.ink)),
                          ),
                      ]),
              ),
            ),
            AppSpace.gapSm,
            _buttons(sf),
          ]),
        );
      }),
      tokenBuilder: (context, tk, lifted) {
        final img = tk.image;
        return LabJar(
          palette: sf.p,
          color: labJarColor(sf.p, sf.right, _key(tk.id)),
          label: tk.text,
          picture: img == null ? null : pic(context, img, 40),
          lifted: lifted,
          hint: tk.hint,
          thick: theme.outline,
        );
      },
    );
    final outcome = AnimatedSwitcher(
      duration: Duration(milliseconds: appMotionOff(context) ? 0 : 280),
      child: _locked
          ? Container(
              key: const ValueKey('lab-result'),
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(color: sf.tint(sf.right, .2), borderRadius: BorderRadius.circular(sf.radius), border: Border.all(color: sf.right.withValues(alpha: .6))),
              child: Row(children: [
                Icon(Icons.auto_awesome_rounded, color: sf.right, size: AppIconSize.lg),
                AppSpace.gapSm,
                Expanded(child: Text(result.isEmpty ? _t('تفاعل رائع!', 'What a reaction!') : result, style: appText(17, w: FontWeight.w700, c: sf.ink, h: 1.4))),
              ]),
            )
          : (_wrongMix
              ? Text(_t('لم يحدث تفاعل، جرّب مزيجًا آخر', 'No reaction. Try another mix'), key: const ValueKey('lab-fail'), textAlign: TextAlign.center, style: appText(16, w: FontWeight.w700, c: sf.onSky))
              : const SizedBox(key: ValueKey('lab-none'), height: 0)),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppReveal(index: 1, group: 'sb$_i', child: board),
      AppSpace.gapMd,
      const SizedBox.shrink(),
      AppSpace.gapMd,
      outcome,
    ]);
  }

  Widget _buttons(StageSurface sf) {
    final canMix = _picked.isNotEmpty && !_locked && !_wrongMix;
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.md, runSpacing: AppSpace.sm, children: [
      StageTile(
        key: const ValueKey('lab-empty'),
        surface: sf,
        expand: false,
        minHeight: AppTouch.min,
        state: StageTileState.idle,
        semanticsLabel: _t('أفرغ الدورق', 'Empty the flask'),
        onTap: _picked.isNotEmpty && !_locked && !_wrongMix ? _empty : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.restart_alt_rounded, size: AppIconSize.md, color: sf.ink),
          AppSpace.gapXs,
          Text(_t('أفرغ', 'Empty'), style: appText(16, w: FontWeight.w700, c: sf.ink)),
        ]),
      ),
      StageTile(
        key: const ValueKey('lab-mix'),
        surface: sf,
        expand: false,
        minHeight: AppTouch.primary,
        state: canMix ? StageTileState.selected : StageTileState.dim,
        semanticsLabel: _t('اخلط', 'Mix'),
        onTap: canMix ? _mix : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.science_rounded, size: AppIconSize.md, color: sf.ink),
          AppSpace.gapSm,
          Text(_t('اخلط!', 'Mix!'), style: appText(18, w: FontWeight.w800, c: sf.ink)),
        ]),
      ),
    ]);
    }
  // ── mcq ──

  Widget _options(StageSurface sf) {
    final opts = (item.body['options'] as List?) ?? const [];
    final order = item.show;
    Widget tile(int idx, int k) {
      final o = opts[k];
      final text = o is Map ? '${o['text'] ?? ''}' : '$o';
      final img = o is Map && o['image'] is String && (o['image'] as String).isNotEmpty ? o['image'] as String : null;
      final pic = widget.imageBuilder ?? _defaultPicture;
      final st = _st[k] ?? StageTileState.idle;
      return AppReveal(
        index: idx + 1,
        group: 'o$_i',
        child: StageReact(
          key: ValueKey('opt-$k'),
          bump: _bump[k] ?? 0,
          shake: sf.calm ? 0 : (_shakeOpt[k] ?? 0),
          child: StageTile(
            surface: sf,
            state: st,
            badge: AppConfig.lang == 'ar' ? const ['أ', 'ب', 'ج', 'د', 'هـ', 'و'][idx.clamp(0, 5)] : String.fromCharCode(65 + idx),
            semanticsLabel: text,
            onTap: _locked ? null : () => _choose(k),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (img != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 48, height: 48, child: pic(context, img, 48))),
                AppSpace.gapSm,
              ],
              Flexible(child: Text(text, textAlign: TextAlign.center, textDirection: textDirectionOf(text, Directionality.of(context)), style: appText(18, w: FontWeight.w600, c: sf.ink, h: 1.3))),
            ]),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 560 && order.length >= 4) {
        const gap = AppSpace.sm;
        final w = (box.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (var j = 0; j < order.length; j++) SizedBox(width: w, child: tile(j, order[j]))]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var j = 0; j < order.length; j++) ...[tile(j, order[j]), if (j < order.length - 1) AppSpace.gapSm],
      ]);
    });
  }
}
