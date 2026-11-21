// lib/features/games/engines/order_engine.dart — the `order` engine (D-1346): the items come shuffled; tap them in
// the right order to place them (tap a placed one to take it back), then Check. No dragging, so it works the same
// with a finger, a mouse, a keyboard and a screen reader. Score = items in their right place, max = items.
// config = {prompt_ar, prompt_en, items: [string]} in the correct order
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

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

class _OrderEngineState extends State<OrderEngine> {
  late final List<String> _items;

  /// The pool, as indexes into _items, in the shuffled order it is shown.
  late final List<int> _pool;
  final List<int> _placed = [];
  bool _checked = false;

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
    if (_left.isEmpty) _revealEnd();
  }

  void _check() {
    setState(() => _checked = true);
    _revealEnd();
  }

  @override
  void initState() {
    super.initState();
    _items = OrderEngine.itemsOf(widget.config);
    _pool = learnShuffle([for (var i = 0; i < _items.length; i++) i], random: widget.random);
  }

  List<int> get _left => [for (final i in _pool) if (!_placed.contains(i)) i];

  /// Right when the TEXT matches (two equal items are interchangeable).
  bool _rightAt(int pos) => _items[_placed[pos]] == _items[pos];

  int get _score => [for (var p = 0; p < _placed.length; p++) if (_rightAt(p)) p].length;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_items.length < 2) {
      return AppEmpty(icon: Icons.format_list_numbered_rounded, title: t('لا توجد عناصر لترتيبها', 'Nothing to put in order'));
    }
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final left = _left;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LearnProgressHeader(
        current: _placed.length,
        total: _items.length,
        label: t('رتّبت ${_placed.length} من ${_items.length}', 'Placed ${_placed.length} of ${_items.length}'),
      ),
      const SizedBox(height: AppSpace.md),
      LearnPrompt(text: prompt.isEmpty ? t('رتّب العناصر بالترتيب الصحيح.', 'Put the items in the right order.') : prompt),
      const SizedBox(height: AppSpace.sm),
      // the answer so far: numbered rows; tap one to send it back
      for (var p = 0; p < _placed.length; p++) ...[
        if (p > 0) const SizedBox(height: AppSpace.xs),
        LearnOptionTile(
          key: ValueKey('order.placed.$p'),
          label: '${p + 1}. ${_items[_placed[p]]}',
          mark: !_checked ? LearnMark.selected : (_rightAt(p) ? LearnMark.correct : LearnMark.wrong),
          onTap: _checked ? null : () => setState(() => _placed.removeAt(p)),
        ),
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
      if (_checked)
        LearnFeedback(
          key: _endKey,
          correct: _score == _items.length,
          title: _score == _items.length
              ? null
              : t('$_score من ${_items.length} في مكانها الصحيح', '$_score of ${_items.length} in the right place'),
          explanation: _score == _items.length
              ? null
              : t('الترتيب الصحيح: ${_items.join('، ')}', 'The right order: ${_items.join(', ')}'),
          actionLabel: t('النتيجة', 'See result'),
          onAction: () => widget.onFinished(_score, _items.length),
        ),
    ]);
  }
}
