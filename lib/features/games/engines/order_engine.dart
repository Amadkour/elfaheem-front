// lib/features/games/engines/order_engine.dart — the `order` engine (D-1346): the items come shuffled; tap them in
// the right order to place them (tap a placed one to take it back), then Check. Score = items in their right place,
// max = items.
// config = {prompt_ar, prompt_en, items: [string]} in the correct order
//
// Games v3 (§1, D-1740): a placed item can also be dragged to another place (a long press on touch, a plain drag
// with a mouse; the screen reader gets Move up / Move down): it lifts, follows the finger 1:1, and its neighbours
// slide aside over `snap` once its centre passes their middle; let go and it snaps into the gap. Tapping still
// places and takes back, so a finger, a mouse, a keyboard and a screen reader all play it. After Check the items
// are revealed top to bottom, `stagger` apart: a right one pulses, a wrong one shakes. "Show the right order" glides
// every item to its place over `settle`.
// Trace (CONTRACT §3): written at Check, one entry per position `i` (ascending) with the item `a` placed there,
// every entry at the Check's time.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/shell/game_tile.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

/// Where a dragged row lands: [rects] are the rows' rects when the drag started (in order), [from] the dragged row,
/// [dy] how far it moved. The new index counts the other rows whose middle is above the dragged centre (pure).
int orderDropIndex(List<Rect> rects, int from, double dy) {
  final centre = rects[from].center.dy + dy;
  var q = 0;
  for (var j = 0; j < rects.length; j++) {
    if (j != from && rects[j].center.dy < centre) q++;
  }
  return q;
}

class OrderEngine extends StatefulWidget {
  const OrderEngine({super.key, required this.config, required this.onFinished, this.random});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  static List<String> itemsOf(Map<String, dynamic> config) => [
        if (config['items'] is List)
          for (final i in config['items'] as List) '$i',
      ];

  @override
  State<OrderEngine> createState() => _OrderEngineState();
}

class _OrderEngineState extends State<OrderEngine> with TickerProviderStateMixin {
  late final List<String> _items;

  /// The pool, as indexes into _items, in the shuffled order it is shown.
  late final List<int> _pool;
  final List<int> _placed = [];
  bool _checked = false;

  /// After Check: how many rows (from the top) show their result; all of them under Reduce motion.
  int _revealed = 0;
  Timer? _revealTimer;

  /// "Show the right order" was pressed: the rows stand in the right order.
  bool _shown = false;

  /// Per item: its row's key (the rect) and its follow offset.
  late final List<GlobalKey> _rowKeys;
  late final List<GameDragOffset> _offsets;

  /// The drag: the item, where it started, the rows' rects then, and the index it would land at.
  int? _dragItem;
  Offset _dragStart = Offset.zero;
  List<Rect> _dragRects = const [];
  int _dragTo = 0;

  /// The Check button / the result card: scrolled into view when it appears, so on a phone it never waits below the
  /// fold under the bottom bar (QA Phase 6).
  final GlobalKey _endKey = GlobalKey();

  void _revealEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _endKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 1,
        duration: AppMotion.of(context).base,
        curve: AppMotion.curve,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _place(int item) {
    setState(() => _placed.add(item));
    final shell = GameShellScope.maybeOf(context);
    shell?.sound(GameSound.tap);
    shell?.report(done: _placed.length);
    if (_left.isEmpty) _revealEnd();
  }

  void _unplace(int pos) {
    if (_dragItem != null) return;
    setState(() => _placed.removeAt(pos));
    GameShellScope.maybeOf(context)?.report(done: _placed.length);
  }

  void _move(int pos, int to) {
    if (to < 0 || to >= _placed.length || _checked) return;
    setState(() => _placed.insert(to, _placed.removeAt(pos)));
  }

  void _check() {
    final shell = GameShellScope.maybeOf(context);
    final ms = shell?.elapsedMs;
    for (var p = 0; p < _placed.length; p++) {
      shell?.record(p, _placed[p], ms: ms);
    }
    final m = GameMotion.of(context);
    setState(() {
      _checked = true;
      _revealed = m.off ? _placed.length : 1;
    });
    if (!m.off && _revealed < _placed.length) {
      _revealTimer = Timer.periodic(m.stagger, (tm) {
        if (!mounted) return tm.cancel();
        setState(() => _revealed++);
        if (_revealed >= _placed.length) tm.cancel();
      });
    }
    shell?.report(done: _items.length, score: _score, correct: _score == _items.length);
    _revealEnd();
  }

  /// Glides every row to its place in the right order (the FLIP: the new places are worked out from the old rects).
  void _showRightOrder() {
    final m = GameMotion.of(context);
    final old = {for (final i in _placed) i: _rectOf(i)};
    if (old.values.any((r) => r == null) || old.isEmpty) {
      setState(() {
        _placed.sort();
        _shown = true;
      });
      return;
    }
    final right = [for (var i = 0; i < _items.length; i++) i];
    // the new top of each row: the first slot's top, then each row's height plus the gap
    var top = old[_placed.first]!.top;
    final newTop = <int, double>{};
    for (final i in right) {
      newTop[i] = top;
      top += old[i]!.height + AppSpace.xs;
    }
    setState(() {
      _placed
        ..clear()
        ..addAll(right);
      _shown = true;
    });
    for (final i in right) {
      final o = _offsets[i];
      o.value = Offset(0, old[i]!.top - newTop[i]!);
      o.glide(Offset.zero, m.settle, GameMotion.turn);
    }
  }

  Rect? _rectOf(int item) {
    final b = _rowKeys[item].currentContext?.findRenderObject();
    if (b is! RenderBox || !b.hasSize || !b.attached) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }

  // ── drag to reorder ───────────────────────────────────────────────────────

  void _onDragStart(int item, Offset global) {
    if (_checked) return;
    final rects = [for (final i in _placed) _rectOf(i)];
    if (rects.any((r) => r == null)) return;
    _dragRects = rects.cast<Rect>();
    _dragStart = global;
    _dragTo = _placed.indexOf(item);
    setState(() => _dragItem = item);
    GameShellScope.maybeOf(context)?.sound(GameSound.tap);
  }

  void _onDragMove(Offset global) {
    final item = _dragItem;
    if (item == null) return;
    final from = _placed.indexOf(item);
    final dy = global.dy - _dragStart.dy;
    _offsets[item].value = Offset(0, dy);
    final to = orderDropIndex(_dragRects, from, dy);
    if (to == _dragTo) return;
    _dragTo = to;
    // the neighbours between the old and the new place slide aside by the dragged row's height + the gap
    final m = GameMotion.of(context);
    final step = _dragRects[from].height + AppSpace.xs;
    for (var j = 0; j < _placed.length; j++) {
      if (j == from) continue;
      final shift = (to > from && j > from && j <= to)
          ? -step
          : (to < from && j >= to && j < from)
              ? step
              : 0.0;
      final o = _offsets[_placed[j]];
      if (o.value.dy != shift) o.glide(Offset(0, shift), m.snap, GameMotion.move);
    }
  }

  void _onDragEnd(Offset global) {
    final item = _dragItem;
    if (item == null) return;
    final m = GameMotion.of(context);
    final from = _placed.indexOf(item);
    final dy = global.dy - _dragStart.dy;
    final to = orderDropIndex(_dragRects, from, dy);
    if (to == from) {
      for (final i in _placed) {
        if (i != item) _offsets[i].glide(Offset.zero, m.snap, GameMotion.move);
      }
      _offsets[item].returnHome(m);
      setState(() => _dragItem = null);
      return;
    }
    // the dragged row's new top from the old rects; it glides from where the finger left it into the gap
    final r = _dragRects;
    final newTop = to < from ? r[to].top : r[to].bottom - r[from].height;
    final residual = r[from].top + dy - newTop;
    for (final i in _placed) {
      if (i != item) {
        _offsets[i]
          ..hold()
          ..value = Offset.zero;
      }
    }
    setState(() {
      _placed.insert(to, _placed.removeAt(from));
      _dragItem = null;
    });
    _offsets[item]
      ..hold()
      ..value = Offset(0, residual)
      ..snapTo(Offset.zero, m);
    GameShellScope.maybeOf(context)?.sound(GameSound.snap);
  }

  void _onDragCancel() {
    final item = _dragItem;
    if (item == null) return;
    final m = GameMotion.of(context);
    for (final i in _placed) {
      if (i != item) _offsets[i].glide(Offset.zero, m.snap, GameMotion.move);
    }
    _offsets[item].returnHome(m);
    setState(() => _dragItem = null);
  }

  @override
  void initState() {
    super.initState();
    _items = OrderEngine.itemsOf(widget.config);
    _pool = learnShuffle([for (var i = 0; i < _items.length; i++) i], random: widget.random);
    _rowKeys = [for (var i = 0; i < _items.length; i++) GlobalKey()];
    _offsets = [for (var i = 0; i < _items.length; i++) GameDragOffset(vsync: this)];
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    for (final o in _offsets) {
      o.dispose();
    }
    super.dispose();
  }

  List<int> get _left => [for (final i in _pool) if (!_placed.contains(i)) i];

  /// Right when the TEXT matches (two equal items are interchangeable).
  bool _rightAt(int pos) => _items[_placed[pos]] == _items[pos];

  int _scoreOf() => [for (var p = 0; p < _placed.length; p++) if (_rightAt(p)) p].length;

  /// The score at Check (the right order shown afterwards does not change it).
  int? _checkedScore;

  int get _score => _checked ? (_checkedScore ??= _scoreOf()) : _scoreOf();

  GameTileState _stateAt(int p) {
    if (!_checked) return GameTileState.selected;
    if (_shown) return GameTileState.hint;
    if (p >= _revealed) return GameTileState.selected;
    return _rightAt(p) ? GameTileState.correct : GameTileState.wrong;
  }

  Widget _row(int p) {
    final item = _placed[p];
    final last = _placed.length - 1;
    final revealed = _checked && !_shown && p < _revealed;
    final sacred = GameShellScope.maybeOf(context)?.sacred ?? false;
    return KeyedSubtree(
      key: _rowKeys[item],
      child: GameDraggable(
        offset: _offsets[item],
        lifted: _dragItem == item,
        enabled: !_checked,
        onStart: (g) => _onDragStart(item, g),
        onMove: _onDragMove,
        onEnd: _onDragEnd,
        onCancel: _onDragCancel,
        child: GameTile(
          key: ValueKey('order.placed.$p'),
          label: '${p + 1}. ${_items[item]}',
          state: _stateAt(p),
          pulse: revealed && _rightAt(p) ? 1 : null,
          shake: revealed && !_rightAt(p) ? 1 : null,
          shakeEnabled: !sacred,
          onTap: _checked ? null : () => _unplace(p),
          semanticsHint: _checked ? null : t('اضغط لإرجاعه، أو اسحبه لتغيير مكانه', 'Tap to take it back, or drag it to move it'),
          actions: _checked
              ? null
              : {
                  if (p > 0) CustomSemanticsAction(label: t('حرّكه لأعلى', 'Move up')): () => _move(p, p - 1),
                  if (p < last) CustomSemanticsAction(label: t('حرّكه لأسفل', 'Move down')): () => _move(p, p + 1),
                },
          trailing: _checked
              ? null
              : Padding(
                  padding: const EdgeInsetsDirectional.only(start: AppSpace.xs),
                  child: Icon(Icons.drag_indicator_rounded, size: AppIconSize.md, color: context.colors.textLight),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_items.length < 2) {
      return AppEmpty(icon: Icons.format_list_numbered_rounded, title: t('لا توجد عناصر لترتيبها', 'Nothing to put in order'));
    }
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final left = _left;
    final inShell = GameShellScope.maybeOf(context) != null;
    final score = _score;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(
          current: _placed.length,
          total: _items.length,
          label: t('رتّبت ${_placed.length} من ${_items.length}', 'Placed ${_placed.length} of ${_items.length}'),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(text: prompt.isEmpty ? t('رتّب العناصر بالترتيب الصحيح.', 'Put the items in the right order.') : prompt),
      const SizedBox(height: AppSpace.sm),
      // the answer so far: numbered rows; tap one to send it back, drag it to move it
      for (var p = 0; p < _placed.length; p++) ...[
        if (p > 0) const SizedBox(height: AppSpace.xs),
        _row(p),
      ],
      if (left.isNotEmpty) ...[
        if (_placed.isNotEmpty) const SizedBox(height: AppSpace.md),
        Text(_placed.isEmpty ? t('اضغط على العنصر الأول:', 'Tap the first item:') : t('اضغط على التالي:', 'Tap the next one:'),
            style: AppType.label(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        LearnChoiceChips(
          keyPrefix: 'order.pool',
          options: [for (final i in left) _items[i]],
          onSelect: (k) => _place(left[k]),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      if (!_checked && left.isEmpty)
        Align(
          key: _endKey,
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.primary(
            key: const ValueKey('order.check'),
            label: t('تحقّق', 'Check'),
            icon: Icons.check_rounded,
            onPressed: _check,
          ),
        ),
      if (_checked) ...[
        if (score < _items.length && !_shown)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              key: const ValueKey('order.show'),
              label: t('اعرض الترتيب الصحيح', 'Show the right order'),
              icon: Icons.sort_rounded,
              onPressed: _showRightOrder,
            ),
          ),
        LearnFeedback(
          key: _endKey,
          correct: score == _items.length,
          title: score == _items.length
              ? null
              : t('$score من ${_items.length} في مكانها الصحيح', '$score of ${_items.length} in the right place'),
          explanation: score == _items.length || _shown
              ? null
              : t('الترتيب الصحيح: ${_items.join('، ')}', 'The right order: ${_items.join(', ')}'),
          actionLabel: t('النتيجة', 'See result'),
          onAction: () => widget.onFinished(score, _items.length),
        ),
      ],
    ]);
  }
}
