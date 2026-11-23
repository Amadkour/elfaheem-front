// lib/features/games/templates/drag_place/drag_place.dart — Drag-to-Place / Body Puzzle (Games v4 T45, CONTRACT §2):
// `classify` items (drag every label to its bucket; with `board` the buckets are spots ON a picture) and `pair` items
// (drag each right-hand word to its left-hand partner). A classify item with `cases` is I'rab Hunter's: it is skipped
// here. The draw's own order (`show` / `show_a` / `show_b`) is kept.
//
//   - a right drop locks in green and the spot shows the piece; a wrong one flies back (a calm round: soft amber, no
//     shake); only the first try of each piece is reported (`s.answer(i, [token, bucket])` / `[a, b]`);
//   - tap a piece, then tap its place (the same board works with a mouse, a keyboard, a screen reader: no drag needed);
//   - the hint lights one piece and the place it belongs to;
//   - with no picture a clean board is drawn; without `board` a classify plays as buckets (with their pictures).
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

class DragPlaceTemplate extends GameTemplate {
  const DragPlaceTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => 'drag_place';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.classify, MechanicKind.pair};
  @override
  Set<ItemType> get accepts => const {ItemType.classify, ItemType.pair};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'اسحب إلى مكانه';
  @override
  String get nameEn => 'Drag to Place';
  @override
  IconData get icon => Icons.pan_tool_alt_rounded;

  @override
  Widget build(GameSession s) => DragPlaceGame(session: s, silent: silent);
}

const DragPlaceTemplate kDragPlace = DragPlaceTemplate();

class DragPlaceGame extends StatefulWidget {
  const DragPlaceGame({super.key, required this.session, this.silent = false, this.reciters, this.advanceMs = 1100, this.boardAspect, this.imageBuilder});
  final GameSession session;
  final bool silent;
  final ReciterLoader? reciters;
  final int advanceMs;

  /// Test hook: the picture's width / height (the app reads it from the picture itself).
  final double? boardAspect;

  /// Test hook: how pictures are drawn (null = the app's network image).
  final DragImageBuilder? imageBuilder;

  @override
  State<DragPlaceGame> createState() => _DragPlaceGameState();
}

class _DragPlaceGameState extends State<DragPlaceGame> {
  int _i = 0;
  bool _done = false;

  // per item: piece -> place it was locked in
  final Map<int, int> _placed = {};
  final Set<int> _tried = {};
  int _wrongSlot = -1, _wrongTok = -1, _shake = 0;
  int _hintTok = -1, _picked = -1;
  bool _locked = false;
  Timer? _timer, _wrongTimer;
  double? _aspect;
  String? _aspectFor;

  GameSession get s => widget.session;
  GameItem get item => s.items[_i];
  bool get _calm => s.calm || s.sacred || item.sacred;
  bool get _isPair => item.type == ItemType.pair;

  List get _tokens => (item.body['tokens'] as List?) ?? const [];
  List get _buckets => (item.body['buckets'] as List?) ?? const [];
  List get _pairs => (item.body['pairs'] as List?) ?? const [];
  Map? get _board => item.body['board'] is Map ? item.body['board'] as Map : null;

  /// Pieces to place: the tokens of a classify, the `b` sides of a pair.
  int get _n => _isPair ? _pairs.length : _tokens.length;

  /// The place piece [k] belongs in (a bucket index, or the pair's own index).
  int _home(int k) {
    if (_isPair) return k;
    final key = (_tokens[k] as Map)['bucket'];
    for (var b = 0; b < _buckets.length; b++) {
      if ((_buckets[b] as Map)['key'] == key) return b;
    }
    return -1;
  }

  List<int> _order(String key, int n) {
    final l = item.body[key];
    return l is List && l.length == n ? [for (final v in l) (v as num).toInt()] : [for (var k = 0; k < n; k++) k];
  }

  String _label(Object? o) => o is Map ? GameText.from(o).of(AppConfig.lang) : '${o ?? ''}';
  String _pieceText(int k) => _isPair ? '${(_pairs[k] as Map)['b']}' : '${(_tokens[k] as Map)['text']}';
  String? _pieceImage(int k) {
    if (_isPair) return null;
    final v = (_tokens[k] as Map)['image'];
    return v is String && v.isNotEmpty ? v : null;
  }

  bool get _hasBoard => !_isPair && _board != null;
  bool _skip(GameItem it) => it.type == ItemType.classify && it.body['cases'] is List && (it.body['cases'] as List).isNotEmpty;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !s.finished) _play();
    });
    _resolveAspect();
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

  /// Reads the board picture's size once, so the spots (fractions of the picture) land where the author put them.
  void _resolveAspect() {
    final url = _hasBoard ? (_board!['image'] as String?) : null;
    if (url == null || url.isEmpty || widget.boardAspect != null || _aspectFor == url) return;
    _aspectFor = url;
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      stream.removeListener(l);
      if (mounted && _aspectFor == url && info.image.height > 0) setState(() => _aspect = info.image.width / info.image.height);
    }, onError: (_, _) => stream.removeListener(l));
    stream.addListener(l);
  }

  void _play() {
    final segs = stageSegments(item);
    if (segs.isEmpty) return;
    final r = s.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(segs, reciter: r is String ? r : null).catchError((Object _) {}));
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
      _placed.clear();
      _tried.clear();
      _wrongSlot = _wrongTok = -1;
      _hintTok = -1;
      _picked = -1;
      _locked = false;
    });
    _resolveAspect();
    _play();
  }

  /// The first unplaced piece in screen order.
  int get _nextPiece {
    for (final k in _order(_isPair ? 'show_b' : 'show', _n)) {
      if (!_placed.containsKey(k)) return k;
    }
    return -1;
  }

  void _hint() {
    if (_locked || _done || _hintTok >= 0) return;
    final k = _nextPiece;
    if (k < 0) return;
    HapticFeedback.selectionClick();
    setState(() => _hintTok = k);
  }

  /// A tap on a piece picks it (again = puts it down); a tap on a place then drops the picked piece there.
  void _onTap(int k) => setState(() => _picked = _picked == k ? -1 : k);

  void _onTapSlot(int slot) {
    if (_picked < 0 || _placed.containsKey(_picked)) return;
    final k = _picked;
    _picked = -1;
    _place(k, slot);
  }

  void _place(int k, int slot) {
    if (_locked || _done || _placed.containsKey(k) || _wrongSlot >= 0) return;
    if (_isPair && _placed.values.contains(slot)) return;
    final right = _home(k) == slot;
    if (_tried.add(k)) s.answer(_i, _isPair ? [slot, k] : [k, slot], hint: _hintTok == k);
    if (right) {
      setState(() {
        _placed[k] = slot;
        if (_hintTok == k) _hintTok = -1;
        if (_placed.length == _n) _locked = true;
      });
      HapticFeedback.mediumImpact();
      if (_locked) _later(widget.advanceMs, _advance);
    } else {
      setState(() {
        _wrongSlot = slot;
        _wrongTok = k;
        _shake++;
      });
      HapticFeedback.heavyImpact();
      if (_calm) _play();
      _wrongTimer?.cancel();
      _wrongTimer = Timer(Duration(milliseconds: appMotionOff(context) ? 150 : 720), () {
        if (mounted) setState(() => _wrongSlot = _wrongTok = -1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StageFrame(session: s, kinds: kDragPlace.kinds, silent: widget.silent, onHint: _hint, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final theme = stageThemeOf(context, calm: s.calm || s.sacred);
    final sf = StageSurface(theme, context);
    final ms = appMotionOff(context) ? 0 : 340;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (wide && _hasBoard ? AppWidth.wide : AppWidth.reading).max),
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

  List<DragSlotData> _slots() {
    final quran = item.sourceKind == 'quran';
    if (_isPair) {
      return [
        for (final p in _order('show_a', _n))
          () {
            final pair = _pairs[p] as Map;
            final img = pair['image'];
            DragToken? tk;
            var st = p == _hintTok ? DragSlotState.hint : DragSlotState.open;
            for (final e in _placed.entries) {
              if (e.value == p) {
                tk = DragToken(id: e.key, text: _pieceText(e.key), quran: quran);
                st = DragSlotState.correct;
              }
            }
            if (tk == null && p == _wrongSlot) {
              tk = DragToken(id: _wrongTok, text: _pieceText(_wrongTok), quran: quran);
              st = DragSlotState.wrong;
            }
            return DragSlotData(
              id: p,
              label: '${pair['a']}',
              image: img is String && img.isNotEmpty ? img : null,
              state: st,
              tokens: [?tk],
            );
          }(),
      ];
    }
    final spots = _board?['spots'];
    return [
      for (var b = 0; b < _buckets.length; b++)
        () {
          final bk = _buckets[b] as Map;
          final at = spots is Map && spots[bk['key']] is List && (spots[bk['key']] as List).length >= 2
              ? Offset(((spots[bk['key']] as List)[0] as num).toDouble().clamp(0.0, 1.0), ((spots[bk['key']] as List)[1] as num).toDouble().clamp(0.0, 1.0))
              : null;
          final toks = [
            for (final e in _placed.entries)
              if (e.value == b) DragToken(id: e.key, text: _pieceText(e.key), quran: quran, image: _pieceImage(e.key)),
          ];
          final hinted = _hintTok >= 0 && _home(_hintTok) == b;
          final wrong = b == _wrongSlot;
          return DragSlotData(
            id: b,
            label: _label(bk['label']),
            image: bk['image'] is String ? bk['image'] as String : null,
            number: _hasBoard ? b + 1 : null,
            capacity: _tokens.length,
            at: at,
            state: wrong
                ? DragSlotState.wrong
                : toks.isNotEmpty && !hinted
                    ? DragSlotState.correct
                    : hinted
                        ? DragSlotState.hint
                        : DragSlotState.open,
            tokens: [
              ...toks,
              if (wrong) DragToken(id: _wrongTok, text: _pieceText(_wrongTok), quran: quran),
            ],
          );
        }(),
    ];
  }

  Widget _round(BuildContext context, AgeTheme theme, StageSurface sf) {
    final it = item;
    final quran = it.sourceKind == 'quran';
    final audio = it.media.audio != null && it.media.audio!.isNotEmpty;
    final prompt = it.prompt.of(AppConfig.lang);
    final label = it.sourceLabel.of(AppConfig.lang);
    final tray = [
      for (final k in _order(_isPair ? 'show_b' : 'show', _n))
        DragToken(
          id: k,
          text: _pieceText(k),
          quran: quran,
          image: _pieceImage(k),
          used: _placed.containsKey(k) || (k == _wrongTok && _wrongSlot >= 0),
          hint: k == _hintTok || k == _picked,
        ),
    ];
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: sf.paper, borderRadius: BorderRadius.circular(sf.radius + 4), boxShadow: sf.lift(blur: 24, dy: 10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
            decoration: BoxDecoration(color: sf.tint(sf.gold, 0.25), borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Text(label, style: appText(13, w: FontWeight.w700, c: sf.ink), textDirection: textDirectionOf(label, Directionality.of(context))),
          ),
          AppSpace.gapSm,
        ],
        if (prompt.isNotEmpty) Text(prompt, textAlign: TextAlign.center, style: appText(19, w: FontWeight.w700, c: sf.ink, h: 1.45)),
        if (audio) ...[
          AppSpace.gapSm,
          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            StageListenButton(surface: sf, onPressed: _play),
            StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: s.reciter?['key'] as String?),
          ]),
        ],
      ]),
    );
    final sample = tray.isEmpty ? prompt : tray.first.text;
    return SingleChildScrollView(
      key: ValueKey('r$_i'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppReveal(index: 0, group: 'dp$_i', child: card),
        AppSpace.gapLg,
        AppReveal(
          index: 1,
          group: 'db$_i',
          child: DragBoard(
            theme: theme,
            imageBuilder: widget.imageBuilder,
            layout: _hasBoard ? DragBoardLayout.board : DragBoardLayout.buckets,
            boardImage: _hasBoard ? _board!['image'] as String? : null,
            boardAspect: widget.boardAspect ?? _aspect ?? 1.5,
            slots: _slots(),
            tray: tray,
            onDrop: _place,
            onTapToken: _onTap,
            onTapSlot: _onTapSlot,
            shakeSlot: _wrongSlot,
            shakeNonce: _shake,
            textDirection: quran ? textDirectionOf(sample, Directionality.of(context)) : null,
            silent: widget.silent,
          ),
        ),
        AppSpace.gapMd,
      ]),
    );
  }
}
