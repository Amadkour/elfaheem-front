// lib/features/games/admin/v4/editors/math_editors.dart — `fraction`, `program` and `combine` editors
// (Games v4 T65, CONTRACT §3). The program grid is edited by tapping cells with a tool (wall / start / goal);
// x grows to the right and y down, in every language: the board is never mirrored.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

class FractionEditor extends StatelessWidget {
  const FractionEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  bool get _isOp => body.containsKey('op');

  List<int> _frac(Object? x) => x is List && x.length == 2 ? [jint(x[0]), jint(x[1], 1)] : [1, 2];

  Widget _fracRow(String label, List<int> f, ValueChanged<List<int>> set) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AppNumberField(label: '$label · ${t('البسط', 'top')}', initialValue: f[0], min: 0, max: 24, onChanged: (v) => set([v?.toInt() ?? 0, f[1]])),
        ),
        AppSpace.gapSm,
        Expanded(
          child: AppNumberField(label: '$label · ${t('المقام', 'bottom')}', initialValue: f[1], min: 1, max: 12, onChanged: (v) => set([f[0], v?.toInt() ?? 1])),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdSelect<bool>(
        label: t('نوع السؤال', 'Question kind'),
        value: _isOp,
        options: [(false, t('كسر مرسوم', 'Colour a fraction of a shape')), (true, t('جمع أو طرح كسرين', 'Add or subtract two fractions'))],
        onChanged: (op) => onChanged(op
            ? {'op': 'add', 'a': [1, 4], 'b': [1, 4]}
            : {'shape': 'pizza', 'n': 1, 'd': 4}),
      ),
      AppSpace.gapSm,
      if (!_isOp) ...[
        EdSelect<String>(
          label: t('الشكل', 'Shape'),
          value: '${body['shape'] ?? 'pizza'}',
          options: [('pizza', t('بيتزا', 'Pizza')), ('bar', t('شريط', 'Bar')), ('field', t('حقل', 'Field'))],
          onChanged: (v) => onChanged({...body, 'shape': v}),
        ),
        AppSpace.gapSm,
        _fracRow(t('الكسر', 'Fraction'), [jint(body['n'], 1), jint(body['d'], 2)], (f) => onChanged({...body, 'n': f[0], 'd': f[1]})),
      ] else ...[
        EdSelect<String>(
          label: t('العملية', 'Operation'),
          value: '${body['op'] ?? 'add'}',
          options: [('add', t('جمع', 'Add')), ('sub', t('طرح', 'Subtract'))],
          onChanged: (v) => onChanged({...body, 'op': v}),
        ),
        AppSpace.gapSm,
        _fracRow(t('الكسر الأول', 'First fraction'), _frac(body['a']), (f) => onChanged({...body, 'a': f})),
        AppSpace.gapSm,
        _fracRow(t('الكسر الثاني', 'Second fraction'), _frac(body['b']), (f) => onChanged({...body, 'b': f})),
        AppSpace.gapSm,
        Text(t('الناتج يجب ألا يكون سالباً.', 'The result must not be negative.'), style: AppType.meta(context)),
      ],
    ]);
  }
}

class ProgramEditor extends StatefulWidget {
  const ProgramEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  @override
  State<ProgramEditor> createState() => _ProgramEditorState();
}

class _ProgramEditorState extends State<ProgramEditor> {
  String _tool = 'wall';

  Json get b => widget.body;
  int get _w => jint(b['w'], 5);
  int get _h => jint(b['h'], 5);
  List<int> get _start => b['start'] is List ? [for (final x in b['start'] as List) jint(x)] : [0, 0, 1];
  List<int> get _goal => b['goal'] is List ? [for (final x in b['goal'] as List) jint(x)] : [_w - 1, _h - 1];
  List<List<int>> get _walls => b['walls'] is List ? [for (final w in b['walls'] as List) if (w is List) [jint(w[0]), jint(w[1])]] : [];

  void _tap(int x, int y) {
    final walls = _walls;
    final i = walls.indexWhere((w) => w[0] == x && w[1] == y);
    switch (_tool) {
      case 'start':
        widget.onChanged({...b, 'start': [x, y, _start.length > 2 ? _start[2] : 1], 'walls': [...walls]..removeWhere((w) => w[0] == x && w[1] == y)});
      case 'goal':
        widget.onChanged({...b, 'goal': [x, y], 'walls': [...walls]..removeWhere((w) => w[0] == x && w[1] == y)});
      default:
        if ((x == _start[0] && y == _start[1]) || (x == _goal[0] && y == _goal[1])) return;
        if (i >= 0) {
          widget.onChanged({...b, 'walls': [...walls]..removeAt(i)});
        } else if (walls.length < 20) {
          widget.onChanged({...b, 'walls': [...walls, [x, y]]});
        }
    }
  }

  void _resize(int w, int h) {
    bool inside(List<int> p) => p[0] < w && p[1] < h;
    widget.onChanged({
      ...b,
      'w': w,
      'h': h,
      'walls': [for (final p in _walls) if (inside(p)) p],
      if (!inside(_start)) 'start': [0, 0, _start.length > 2 ? _start[2] : 1],
      if (!inside(_goal)) 'goal': [w - 1, h - 1],
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cmds = b['cmds'] is List ? {for (final x in b['cmds'] as List) '$x'} : <String>{'F', 'L', 'R'};
    final walls = _walls;
    final dirs = [t('شمال', 'North'), t('شرق', 'East'), t('جنوب', 'South'), t('غرب', 'West')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: AppNumberField(label: t('العرض', 'Width'), initialValue: _w, min: 3, max: 8, onChanged: (v) => _resize(v?.toInt() ?? 5, _h))),
        AppSpace.gapSm,
        Expanded(child: AppNumberField(label: t('الارتفاع', 'Height'), initialValue: _h, min: 3, max: 8, onChanged: (v) => _resize(_w, v?.toInt() ?? 5))),
      ]),
      EdTitle(t('اللوحة', 'The board'), hint: t('اختر أداة ثم المس المربعات (حتى 20 حائطاً).', 'Pick a tool, then tap cells (up to 20 walls).')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final tool in [('wall', t('حائط', 'Wall')), ('start', t('البداية', 'Start')), ('goal', t('الهدف', 'Goal'))])
          tool.$1 == _tool
              ? AppButton.primary(label: tool.$2, size: AppButtonSize.sm, onPressed: () {})
              : AppButton.secondary(label: tool.$2, size: AppButtonSize.sm, onPressed: () => setState(() => _tool = tool.$1)),
      ]),
      AppSpace.gapSm,
      // the board is never mirrored: x to the right, y down, in both directions of text
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: _w / _h,
              child: Column(children: [
                for (var y = 0; y < _h; y++)
                  Expanded(
                    child: Row(children: [
                      for (var x = 0; x < _w; x++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: '$x,$y',
                            child: GestureDetector(
                              onTap: () => _tap(x, y),
                              child: Container(
                                margin: const EdgeInsets.all(AppBorder.hairline),
                                decoration: BoxDecoration(
                                  color: walls.any((p) => p[0] == x && p[1] == y)
                                      ? c.textMedium
                                      : (x == _goal[0] && y == _goal[1])
                                          ? c.success
                                          : (x == _start[0] && y == _start[1])
                                              ? c.primary
                                              : c.cardBg2,
                                  borderRadius: BorderRadius.circular(AppRadius.chip / AppBorder.focus),
                                ),
                                alignment: Alignment.center,
                                child: (x == _start[0] && y == _start[1])
                                    ? Icon(Icons.smart_toy_rounded, size: AppIconSize.sm, color: c.onHero)
                                    : (x == _goal[0] && y == _goal[1])
                                        ? Icon(Icons.flag_rounded, size: AppIconSize.sm, color: c.onHero)
                                        : null,
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
      ),
      AppSpace.gapSm,
      EdSelect<int>(
        label: t('اتجاه الروبوت في البداية', 'Which way the robot faces'),
        value: (_start.length > 2 ? _start[2] : 1).clamp(0, 3),
        options: [for (var i = 0; i < 4; i++) (i, dirs[i])],
        onChanged: (v) => widget.onChanged({...b, 'start': [_start[0], _start[1], v]}),
      ),
      EdTitle(t('الأوامر المتاحة', 'Commands the child can use')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final cmd in [('F', t('تقدّم', 'Forward')), ('L', t('يسار', 'Left')), ('R', t('يمين', 'Right')), ('LOOP', t('كرّر', 'Repeat'))])
          FilterChip(
            label: Text(cmd.$2),
            selected: cmds.contains(cmd.$1),
            onSelected: (on) {
              final next = {...cmds};
              on ? next.add(cmd.$1) : next.remove(cmd.$1);
              widget.onChanged({...b, 'cmds': ['F', 'L', 'R', 'LOOP'].where(next.contains).toList()});
            },
          ),
      ]),
      AppSpace.gapSm,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: AppNumberField(label: t('أقصى عدد أوامر', 'Most commands'), initialValue: jint(b['max'], 10), min: 1, max: 30, onChanged: (v) => widget.onChanged({...b, 'max': v?.toInt() ?? 10}))),
        AppSpace.gapSm,
        Expanded(child: AppNumberField(label: t('الحل الأمثل', 'Best solution'), initialValue: jint(b['par'], 5), min: 1, max: 30, onChanged: (v) => widget.onChanged({...b, 'par': v?.toInt() ?? 5}))),
      ]),
    ]);
  }
}

class CombineEditor extends StatelessWidget {
  const CombineEditor({super.key, required this.body, required this.onChanged});
  final Json body;
  final ValueChanged<Json> onChanged;

  String _label(Json i) {
    final l = i['label'];
    return l is Map ? '${l['ar'] ?? l['en'] ?? ''}' : '${l ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final ing = jlist(body['ingredients']);
    final answer = {for (final a in (body['answer'] is List ? body['answer'] as List : const [])) '$a'};
    String newKey() {
      var n = ing.length + 1;
      while (ing.any((i) => i['key'] == 'i$n')) {
        n++;
      }
      return 'i$n';
    }

    void emit(List<Json> next, Set<String> ans) => onChanged({
          ...body,
          'ingredients': next,
          'answer': [for (final i in next) if (ans.contains('${i['key']}')) '${i['key']}'],
        });

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdTitle(t('المكوّنات', 'Ingredients'), hint: t('من 3 إلى 8 مكوّنات.', '3 to 8 ingredients.')),
      for (var i = 0; i < ing.length; i++)
        EdRow(
          key: edIndexKey('ig', i, ing.length),
          onRemove: ing.length > 3 ? () => emit([...ing]..removeAt(i), {...answer}..remove('${ing[i]['key']}')) : null,
          child: Column(children: [
            EdText(
              label: t('المكوّن ${i + 1} · عربي', 'Ingredient ${i + 1} · Arabic'),
              value: jmap(ing[i]['label'])['ar']?.toString() ?? '',
              onChanged: (v) {
                final next = [...ing];
                next[i] = {...next[i], 'label': {...jmap(next[i]['label']), 'ar': v}};
                emit(next, answer);
              },
            ),
            AppSpace.gapSm,
            EdText(
              label: t('المكوّن ${i + 1} · إنجليزي', 'Ingredient ${i + 1} · English'),
              value: jmap(ing[i]['label'])['en']?.toString() ?? '',
              ltr: true,
              onChanged: (v) {
                final next = [...ing];
                next[i] = {...next[i], 'label': {...jmap(next[i]['label']), 'en': v}};
                emit(next, answer);
              },
            ),
          ]),
        ),
      if (ing.length < 8)
        EdAdd(label: t('إضافة مكوّن', 'Add an ingredient'), onPressed: () => emit([...ing, {'key': newKey(), 'label': {'ar': '', 'en': ''}}], answer)),
      EdTitle(t('المكوّنات الصحيحة للتركيب', 'Which ones make the mix'), hint: t('اختر من 2 إلى 4.', 'Pick 2 to 4.')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (var i = 0; i < ing.length; i++)
          FilterChip(
            label: Text(_label(ing[i]).isEmpty ? '${i + 1}' : _label(ing[i])),
            selected: answer.contains('${ing[i]['key']}'),
            onSelected: (on) {
              final k = '${ing[i]['key']}';
              emit(ing, on ? {...answer, k} : ({...answer}..remove(k)));
            },
          ),
      ]),
      AppSpace.gapSm,
      EdSelect<String>(
        label: t('المؤثر عند النجاح', 'Effect when it works'),
        value: '${body['fx'] ?? 'fizz'}',
        options: [
          ('fizz', t('فقاعات', 'Fizz')),
          ('color', t('تغيّر اللون', 'Colour change')),
          ('glow', t('توهّج', 'Glow')),
          ('smoke', t('دخان', 'Smoke')),
          ('freeze', t('تجمّد', 'Freeze')),
        ],
        onChanged: (v) => onChanged({...body, 'fx': v}),
      ),
      AppSpace.gapSm,
      EdBilingual(
        label: t('اسم الناتج (اختياري)', 'Result name (optional)'),
        value: jmap(body['result']),
        maxLines: 1,
        onChanged: (v) => onChanged({...body, 'result': v['ar'] == null && v['en'] == null ? null : v}),
      ),
    ]);
  }
}
