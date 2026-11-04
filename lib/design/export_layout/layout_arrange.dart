// lib/design/export_layout/layout_arrange.dart
//
// Steps 2 and 3 of the export / design page and the live preview pane:
//
//   LayoutLayoutStep   "Layout": how the items are laid out — table, list (1 – 4 columns), cards (1 – 4 per line),
//                      grid (2×2, 3×3 …, the cards fill the page), one page per item (not for Excel) — the settings
//                      for large lists (items per page, columns, gaps), sort / group (a page per group) / totals,
//                      and the computed columns entry
//   LayoutDesignStep   "Design": the items and the fixed parts (header, before / after the items, footer, page) on
//                      the same canvas engine behind a switcher. Every (language, part) editor stays mounted while
//                      the person switches, so each canvas keeps its undo history
//   LayoutPreviewPane  the server's first page next to the editing (wide screens) or in a sheet (phones)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../features/admin/admin_common.dart' show t;
import '../app_kit.dart';
import '../app_tokens.dart';
import '../studio/studio.dart';
import 'layout_flow_controller.dart';
import 'layout_model.dart';
import 'layout_start.dart';
import 'layout_steps.dart';

/// Wide enough for the live preview to sit next to the editing.
const double kLayoutLivePreviewMin = 1100;

/// The width of that side pane.
const double kLayoutPreviewPaneWidth = 340;

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Layout
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The "Computed columns" entry: how many there are and a button that opens the editor.
class LayoutComputedEntry extends StatelessWidget {
  const LayoutComputedEntry({super.key, required this.flow, required this.onOpen, this.compact = false});
  final LayoutFlowController flow;
  final VoidCallback onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final n = flow.doc.computed.length;
    final label = n == 0 ? t('أعمدة محسوبة', 'Computed columns') : '${t('أعمدة محسوبة', 'Computed columns')} ($n)';
    if (compact) {
      return TextButton.icon(key: const ValueKey('layout-computed-open'), onPressed: onOpen, icon: const Icon(Icons.functions_rounded, size: 18), label: Text(label));
    }
    final c = context.colors;
    return LayoutSection(
      title: t('أعمدة محسوبة', 'Computed columns'),
      subtitle: t('أنشئ عمودًا جديدًا من قواعد بسيطة (مثل: ناجح إذا الدرجة ≥ 50)؛ يظهر في كل قوائم الحقول.', 'Make a new column from simple rules (like Pass when the score is ≥ 50); it shows up in every field list.'),
      children: [
        if (n > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final f in flow.doc.computedFields) Chip(avatar: Icon(Icons.functions_rounded, size: 16, color: c.primary), label: Text(f.label(flow.lang))),
            ]),
          ),
        OutlinedButton.icon(
          key: const ValueKey('layout-computed-open'),
          onPressed: onOpen,
          icon: const Icon(Icons.functions_rounded),
          label: Text(n == 0 ? t('إضافة عمود محسوب', 'Add a computed column') : t('تعديل الأعمدة المحسوبة', 'Edit the computed columns')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        ),
      ],
    );
  }
}

class LayoutLayoutStep extends StatelessWidget {
  const LayoutLayoutStep({super.key, required this.flow, required this.onComputed});
  final LayoutFlowController flow;
  final VoidCallback onComputed;

  static const _grids = <(int, int)>[(2, 2), (2, 3), (3, 3), (3, 4), (4, 4)];

  void _forAll(void Function(LayoutDesign d) fn) {
    for (final l in flow.doc.languages) {
      final d = flow.doc.designs[l];
      if (d != null) fn(d);
    }
    flow.changed();
  }

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final kind = f.layoutKind;
    final lang = f.lang;
    Widget kindCard(String id, String key, String title, String hint, LayoutThumbSpec spec, VoidCallback pick) => LayoutChoiceCard(
          key: ValueKey('layout-kind-$key'),
          title: title,
          hint: hint,
          picture: LayoutDesignThumb(spec: spec, height: 72),
          selected: kind == id,
          onTap: () {
            if (kind != id) pick();
          },
        );
    LayoutPreset preset(String k) => kLayoutPresets.firstWhere((p) => p.key == k);
    Widget stepperInt(String label, int value, int max, ValueChanged<int> on, {Key? key}) => SizedBox(
          width: 220,
          child: StudioStepper(key: key, label: label, value: value.toDouble(), min: 0, max: max.toDouble(), step: 1, onChanged: (v) => on(v.round())),
        );
    final perPageLabel = t('عناصر كل صفحة (0 = ما يتسع)', 'Items per page (0 = as many as fit)');

    final arrange = <Widget>[];
    switch (kind) {
      case 'list':
        arrange.addAll([
          StudioPropField(
            label: t('أعمدة القائمة', 'List columns'),
            child: StudioSegmented<int>(
              key: const ValueKey('layout-list-columns'),
              segments: const [StudioSegment(value: 1, label: '1'), StudioSegment(value: 2, label: '2'), StudioSegment(value: 3, label: '3'), StudioSegment(value: 4, label: '4')],
              value: d.list.columns,
              onChanged: (n) => _forAll((x) => x.list.columns = n),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            if (d.list.columns > 1)
              SizedBox(
                width: kLayoutStepperWidth,
                child: StudioStepper(label: t('المسافة بين الأعمدة (مم)', 'Column gap (mm)'), value: d.list.columnGap, min: 0, max: 30, step: 1, onChanged: (v) => _forAll((x) => x.list.columnGap = v)),
              ),
            stepperInt(perPageLabel, d.list.itemsPerPage, 500, f.setItemsPerPage, key: const ValueKey('layout-items-per-page')),
          ]),
        ]);
      case 'cards':
        arrange.addAll([
          StudioPropField(
            label: t('البطاقات في السطر', 'Cards per line'),
            child: StudioSegmented<int>(
              key: const ValueKey('layout-cards-per-line'),
              segments: const [StudioSegment(value: 1, label: '1'), StudioSegment(value: 2, label: '2'), StudioSegment(value: 3, label: '3'), StudioSegment(value: 4, label: '4')],
              value: d.row.perLine,
              onChanged: (n) => _forAll((x) => layoutSetPerLine(x, n)),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          stepperInt(perPageLabel, d.row.perPage, 500, f.setItemsPerPage, key: const ValueKey('layout-items-per-page')),
        ]);
      case 'grid':
        arrange.addAll([
          StudioPropField(
            label: t('حجم الشبكة (أعمدة × أسطر)', 'Grid size (columns × lines)'),
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final (n, r) in _grids)
                ChoiceChip(
                  key: ValueKey('layout-grid-$n-$r'),
                  label: Text('$n×$r'),
                  selected: d.row.perLine == n && d.row.perPage == n * r,
                  onSelected: (_) => f.setLayout('custom', perLine: n, perPage: n * r, fill: true),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(t('تُحسب مقاسات البطاقات لتملأ الصفحة.', 'The cards are sized so they fill the page.'), style: appText(12, c: context.colors.textMedium)),
        ]);
      case 'table':
        arrange.add(stepperInt(perPageLabel, d.table.itemsPerPage, 500, f.setItemsPerPage, key: const ValueKey('layout-items-per-page')));
      default:
        arrange.add(Text(t('كل عنصر في صفحة كاملة: مناسب للشهادات وبطاقات التعريف.', 'Every item gets a full page: good for certificates and profile sheets.'), style: appText(12.5, c: context.colors.textMedium)));
    }

    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      LayoutSection(
        title: t('كيف تريد عرض العناصر؟', 'How do you want to lay the items out?'),
        subtitle: t('اختر الشكل، ثم اضبط التفاصيل أدناه.', 'Pick the shape, then adjust the details below.'),
        children: [
          LayoutCardGrid(min: 150, children: [
            kindCard('table', 'table', t('جدول', 'Table'), t('أعمدة بعناوين', 'Columns with headings'), preset('table').thumb, () => f.applyPreset(preset('table'))),
            kindCard('list', 'list', t('قائمة', 'List'), t('سطر لكل عنصر، بعمود أو أكثر', 'A line per item, in 1 – 4 columns'), preset('list').thumb, () => f.applyPreset(preset('list'))),
            kindCard('cards', 'cards', t('بطاقات', 'Cards'), t('1 – 4 بطاقات في السطر', '1 – 4 cards per line'), preset('cards2').thumb, () => f.applyPreset(preset('cards'))),
            kindCard('grid', 'grid', t('شبكة', 'Grid'), t('2×2 أو 3×3 تملأ الصفحة', '2×2 or 3×3 filling the page'), preset('grid2').thumb, () => f.applyPreset(preset('grid2'))),
            if (!f.isXlsx) kindCard('page', 'page', t('صفحة لكل عنصر', 'One page per item'), t('شهادات وبطاقات تعريف', 'Certificates and profile sheets'), preset('page').thumb, () => f.applyPreset(preset('page'))),
          ]),
        ],
      ),
      LayoutSection(
        key: const ValueKey('layout-arrange'),
        title: t('القوائم الكبيرة', 'Large lists'),
        subtitle: lang == 'ar' ? 'أعمدة وبطاقات متجاورة وعدد العناصر في كل صفحة.' : 'Columns, cards side by side and the number of items on a page.',
        children: arrange,
      ),
      LayoutComputedEntry(flow: f, onOpen: onComputed),
      LayoutSortGroupTotals(flow: f),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Design
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class LayoutDesignStep extends StatefulWidget {
  const LayoutDesignStep({super.key, required this.flow, required this.width, required this.onComputed});
  final LayoutFlowController flow;
  final double width;
  final VoidCallback onComputed;

  @override
  State<LayoutDesignStep> createState() => _LayoutDesignStepState();
}

class _LayoutDesignStepState extends State<LayoutDesignStep> {
  /// 0 = the items · 1 – 4 = the fixed parts (header, before, after, footer) · 5 = the page.
  int _part = 0;

  /// The (language, part) editors that were opened and stay mounted, and the design epoch they were built for.
  final _opened = <String>{};

  /// The widget of each opened editor as it was last built while its language was the current one. The steps read
  /// `flow.lang`, so a hidden language's editor must not be rebuilt (it would draw the other design): it is given the
  /// SAME widget instance, which Flutter leaves alone, and keeps its state and undo history.
  final _built = <String, Widget>{};
  int _epoch = -1;

  /// The rows' look (zebra, separator, gap …) on a canvas page: its own chip, so the canvas keeps the whole height.
  bool _rowOptionsChip(LayoutFlowController f) => (f.design.mode == 'custom') && widget.width >= kLayoutCanvasMin;

  String _partLabel(int p, LayoutFlowController f) => switch (p) {
        0 => switch (f.design.mode) {
              'list' => t('الحقول', 'Fields'),
              'table' => t('الأعمدة', 'Columns'),
              'page' => t('تصميم الصفحة', 'Page design'),
              _ => t('بطاقة العنصر', 'Item card'),
            },
        5 => t('الصفحة', 'Page'),
        6 => t('خيارات الصفوف', 'Row options'),
        _ => layoutSlotLabel(LayoutBandSlot.values[p - 1]),
      };

  Widget _body(String key, LayoutFlowController f) {
    final part = int.parse(key.split('|').last);
    if (part == 0) return LayoutItemsStep(flow: f, width: widget.width);
    if (part == 5) return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [LayoutPageOptions(flow: f)]);
    if (part == 6) return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [LayoutRowOptions(flow: f)]);
    return LayoutBandPart(flow: f, slot: LayoutBandSlot.values[part - 1], width: widget.width);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flow;
    if (_epoch != f.designEpoch) {
      _opened.clear();
      _built.clear();
      _epoch = f.designEpoch;
    }
    if (_part == 6 && !_rowOptionsChip(f)) _part = 0;
    final cur = '${f.lang}|$_part';
    _opened.add(cur);
    final parts = [0, if (_rowOptionsChip(f)) 6, 1, 2, 3, 4, 5];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ONE line, scrolling sideways: the canvas below keeps the height on small windows
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 0),
        child: Row(children: [
          for (final p in parts)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: ChoiceChip(
                key: ValueKey(switch (p) {
                  0 => 'layout-part-items',
                  5 => 'layout-band-page',
                  6 => 'layout-part-rows',
                  _ => 'layout-band-${LayoutBandSlot.values[p - 1].key}',
                }),
                avatar: p == 5 ? const Icon(Icons.description_outlined, size: 18) : null,
                label: Text(_partLabel(p, f)),
                selected: _part == p,
                onSelected: (_) => setState(() => _part = p),
              ),
            ),
          LayoutComputedEntry(flow: f, onOpen: widget.onComputed, compact: true),
        ]),
      ),
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          for (final k in _opened)
            Offstage(
              key: ValueKey('keep-$k-$_epoch'),
              offstage: k != cur,
              child: ExcludeFocus(
                excluding: k != cur,
                child: TickerMode(enabled: k == cur, child: k == cur ? (_built[k] = _body(k, f)) : (_built[k] ??= _body(k, f))),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Live preview
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The server's pages with the notes under them: refreshes by itself a moment after each edit (the controller
/// debounces), keeps the old page on screen meanwhile and the page the person is on.
class LayoutPreviewPane extends StatelessWidget {
  const LayoutPreviewPane({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = flow;
    final stale = f.previewStale(f.lang);
    final issues = f.issues;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(t('معاينة مباشرة', 'Live preview'), style: appText(14, w: FontWeight.w700, c: c.textDark))),
        if (f.previewLoading)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else if (stale && f.previewError == null)
          Text(t('بعد لحظات…', 'In a moment…'), key: const ValueKey('layout-pane-stale'), style: appText(12, c: c.textMedium)),
      ]),
      const SizedBox(height: AppSpace.xs),
      Expanded(child: LayoutPreviewPages(flow: f)),
      if (issues.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: SingleChildScrollView(child: LayoutIssuesList(issues: issues, key: const ValueKey('layout-pane-issues'))),
        ),
      ],
    ]);
  }
}
