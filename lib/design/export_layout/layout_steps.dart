// lib/design/export_layout/layout_steps.dart
//
// The building blocks of the designer's steps, each a widget over the [LayoutFlowController]:
//
//   layout_start.dart   the start screen (format, language, gallery, Export now), thumbnails, the run panel
//   layout_arrange.dart the Layout step, the Design step (items + fixed parts behind one switcher), the live pane
//   here                LayoutItemsStep (the Row Designer: canvas + live row preview with the item browser, or the
//                       field editor for list / table), LayoutRowOptions (zebra, separator, keep together, per line),
//                       LayoutSortGroupTotals, LayoutBandPart (one fixed part on the canvas), LayoutPageOptions
//                       (size, orientation, font, frame, watermark), LayoutPreviewStep (the server's pages, the
//                       notes, Export with progress / cancel, save as a template)
//
// Phones (< 720 px) get the simple form of the items and the fixed parts: starter designs, field picking, toggles —
// the canvas is for tablets and desktops.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../features/admin/admin_common.dart' show t;
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../studio/studio.dart';
import 'layout_canvas.dart';
import 'layout_element_view.dart';
import 'layout_flow_controller.dart';
import 'layout_logic.dart';
import 'layout_model.dart';
import 'layout_props.dart';
import 'layout_start.dart' show LayoutExcelNote, LayoutRunPanel;

/// Wide enough for the canvas (else the simple phone form).
const double kLayoutCanvasMin = 720;

/// Wide enough to dock the properties at the side.
const double kLayoutDockMin = 1000;

/// Widths of the option controls (steppers, pickers) and the preview's side panel.
const double kLayoutStepperWidth = 170, kLayoutPickWidth = 180, kLayoutLabelWidth = 150, kLayoutMarginWidth = 140;
const double kLayoutSwitchWidth = 260, kLayoutPlacementWidth = 240, kLayoutPreviewSide = 380, kLayoutPreviewHeight = 460;

List<LayoutFieldOption> layoutFieldOptions(LayoutFlowController f) =>
    [for (final x in f.allFields) (key: x.key, label: x.label(f.lang), numeric: x.numeric)];

/// A titled card of a step.
class LayoutSection extends StatelessWidget {
  const LayoutSection({super.key, required this.title, this.subtitle, required this.children, this.trailing});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: appText(15.5, w: FontWeight.w700, c: c.textDark))),
          ?trailing,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(subtitle!, style: appText(12.5, c: c.textMedium)),
        ],
        const SizedBox(height: AppSpace.sm),
        ...children,
      ]),
    );
  }
}

/// A selectable card: icon or a drawing, a title and a hint.
class LayoutChoiceCard extends StatelessWidget {
  const LayoutChoiceCard({super.key, required this.title, required this.hint, required this.selected, required this.onTap, this.icon, this.picture});
  final String title, hint;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? picture;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title — $hint',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardAll,
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: selected ? c.primaryTint : c.cardBg,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (picture != null) ...[picture!, const SizedBox(height: AppSpace.xs)],
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 20, color: selected ? c.primary : c.textMedium), const SizedBox(width: AppSpace.xs)],
                Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark))),
                if (selected) Icon(Icons.check_circle_rounded, size: 20, color: c.primary),
              ]),
              const SizedBox(height: AppSpace.xxs),
              Text(hint, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Cards in a responsive grid ([min] px a card).
class LayoutCardGrid extends StatelessWidget {
  const LayoutCardGrid({super.key, required this.children, this.min = 200});
  final List<Widget> children;
  final double min;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = (box.maxWidth / min).floor().clamp(1, children.length);
        final w = (box.maxWidth - AppSpace.sm * (n - 1)) / n;
        return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Step 3 — the items
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The add menu of the Row Designer.
List<LayoutAddOption> layoutRowAddOptions(LayoutFlowController f) {
  final first = f.allFields.isEmpty ? null : f.allFields.first;
  return [
    LayoutAddOption(t('حقل', 'Field'), Icons.data_object_rounded,
        (id) => LayoutElement(id: id, kind: 'field', y: 2, w: 40, h: 6, name: first?.label(f.lang), bind: first?.bind(), style: LayoutStyle(maxLines: 1))),
    LayoutAddOption(t('نص ثابت', 'Text'), Icons.text_fields_rounded,
        (id) => LayoutElement(id: id, kind: 'text', y: 2, w: 30, h: 5, value: t('نص', 'Text'), style: LayoutStyle(size: 8, color: '#667085', maxLines: 1))),
    LayoutAddOption(t('شارة', 'Badge'), Icons.label_outline_rounded,
        (id) => LayoutElement(id: id, kind: 'badge', y: 2, w: 22, h: 6, bind: first?.bind(), style: LayoutStyle(size: 8, align: 'center', bg: '#F2F4F7', radius: 3, maxLines: 1))),
    LayoutAddOption(t('رقم العنصر', 'Item number'), Icons.tag_rounded,
        (id) => LayoutElement(id: id, kind: 'text', y: 2, w: 8, h: 6, name: t('الرقم', 'Number'), computed: LayoutComputed(op: 'index'), style: LayoutStyle(size: 9, weight: 700, align: 'center'))),
    LayoutAddOption(t('صورة', 'Image'), Icons.image_outlined, (id) => LayoutElement(id: id, kind: 'image', y: 2, w: 12, h: 12, fit: 'contain', style: LayoutStyle(padding: 0))),
    LayoutAddOption(t('خط', 'Line'), Icons.horizontal_rule_rounded,
        (id) => LayoutElement(id: id, kind: 'line', y: 1, w: 60, h: 1, style: LayoutStyle(border: LayoutBorder(width: .3, color: '#D0D5DD')))),
    LayoutAddOption(t('مربع', 'Box'), Icons.crop_square_rounded,
        (id) => LayoutElement(id: id, kind: 'rect', y: 1, w: 20, h: 10, style: LayoutStyle(bg: '#F2F4F7', radius: 1.5, padding: 0))),
    layoutEllipseAddOption(),
  ];
}

class LayoutItemsStep extends StatefulWidget {
  const LayoutItemsStep({super.key, required this.flow, required this.width});
  final LayoutFlowController flow;
  final double width;

  @override
  State<LayoutItemsStep> createState() => _LayoutItemsStepState();
}

class _LayoutItemsStepState extends State<LayoutItemsStep> {

  @override
  Widget build(BuildContext context) {
    final f = widget.flow;
    final d = f.design;
    if (d.mode == 'list' || d.mode == 'table') {
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        LayoutSection(
          title: d.mode == 'list' ? t('حقول السطر', 'Fields of the line') : t('أعمدة الجدول', 'Table columns'),
          subtitle: t('اختر الحقول ورتّبها بالسحب.', 'Pick the fields and drag to order them.'),
          children: [LayoutFieldsEditor(flow: f)],
        ),
        LayoutSection(title: t('معاينة سريعة', 'Quick look'), children: [LayoutItemsPreview(flow: f)]),
        LayoutRowOptions(flow: f),
      ]);
    }
    if (widget.width < kLayoutCanvasMin) {
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        LayoutSection(title: t('بطاقة العنصر', 'The item card'), children: [LayoutRowPreview(flow: f)]),
        LayoutSection(
          title: t('ما تعرضه البطاقة', 'What the card shows'),
          subtitle: t('للتصميم الحر افتح الصفحة على شاشة أكبر.', 'For free design open this page on a larger screen.'),
          children: [LayoutCardFieldsEditor(flow: f)],
        ),
        LayoutRowOptions(flow: f),
      ]);
    }
    final c = context.colors;
    final row = d.row;
    final cw = row.cardWidth(d.page.contentWidth);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: LayoutCanvasEditor(
            key: ValueKey('row-${f.lang}'),
            elements: row.elements,
            width: cw,
            height: d.mode == 'page' ? mm(d.page.contentHeight) : row.height,
            rtl: d.page.rtl,
            pageFont: d.page.font,
            pageFontSize: d.page.fontSize,
            lang: f.lang,
            fields: layoutFieldOptions(f),
            addOptions: layoutRowAddOptions(f),
            newId: () => d.newId('r'),
            onChanged: f.changed,
            upload: (b, n) => layoutUpload(f, b, n),
            vars: f.varsFor(f.lang),
            fieldOf: f.fieldOf,
            background: row.background,
            border: row.border,
            radius: row.radius,
            wide: widget.width >= kLayoutDockMin,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
          child: LayoutRowPreview(flow: f, maxHeight: 150),
        ),
      ]),
    );
  }
}

/// Uploads an image for the design; notices on failure. The asset id, or null.
Future<String?> layoutUpload(LayoutFlowController f, Uint8List bytes, String name) async {
  if (bytes.length > 2 * 1024 * 1024) {
    showAppNotice(t('الصورة أكبر من 2 ميجابايت', 'The image is larger than 2 MB'), error: true);
    return null;
  }
  final r = await f.api.uploadAsset(bytes, name);
  if (!r.ok || r.data!.isEmpty) {
    showAppNotice(r.error ?? t('تعذّر رفع الصورة', 'Could not upload the image'), error: true);
    return null;
  }
  return r.data;
}

/// The live row preview: the card(s) for the real items, rules applied, with "‹ item 3 of 120 ›".
class LayoutRowPreview extends StatelessWidget {
  const LayoutRowPreview({super.key, required this.flow, this.maxHeight = 220});
  final LayoutFlowController flow;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final c = context.colors;
    final d = f.design;
    final items = f.items;
    final n = items.length;
    if (n == 0) {
      return Text(t('لا توجد عناصر لعرضها.', 'There are no items to show.'), style: appText(13, c: c.textMedium));
    }
    final i = f.itemIndex.clamp(0, n - 1);
    final row = d.row;
    final w = d.page.contentWidth;
    final cw = row.cardWidth(w);
    final vars = f.varsFor(f.lang);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('معاينة بالعناصر الحقيقية', 'Preview with the real items'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textDark)),
      Row(children: [
        IconButton(
          key: const ValueKey('layout-item-prev'),
          tooltip: t('العنصر السابق', 'Previous item'),
          onPressed: i > 0 ? () => f.browse(-1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text('${t('العنصر', 'Item')} ${i + 1} ${t('من', 'of')} $n',
              key: const ValueKey('layout-item-label'), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: c.textMedium)),
        ),
        IconButton(
          key: const ValueKey('layout-item-next'),
          tooltip: t('العنصر التالي', 'Next item'),
          onPressed: i < n - 1 ? () => f.browse(1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
      const SizedBox(height: AppSpace.xs),
      LayoutBuilder(builder: (context, box) {
        final scale = ((box.maxWidth - 2 * AppSpace.xs) / w).clamp(.5, 6.0).toDouble();
        final fit = row.height * scale > maxHeight ? maxHeight / (row.height * scale) : 1.0;
        final s = scale * fit;
        final cards = [for (var k = 0; k < row.perLine && i + k < n; k++) i + k];
        return Container(
          color: kStudioPaper,
          padding: const EdgeInsets.all(AppSpace.xs),
          alignment: AlignmentDirectional.centerStart,
          child: Directionality(
            textDirection: d.page.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Wrap(spacing: row.gap * s, children: [
              for (final k in cards)
                LayoutBoxView(
                  elements: row.elements,
                  width: cw,
                  height: row.height,
                  scale: s,
                  rtl: d.page.rtl,
                  pageFont: d.page.font,
                  pageFontSize: d.page.fontSize,
                  item: items[k],
                  index: k + 1,
                  lang: f.lang,
                  vars: vars,
                  fieldOf: f.fieldOf,
                  background: row.zebra != null && k.isOdd ? row.zebra : row.background,
                  border: row.border,
                  radius: row.radius,
                ),
            ]),
          ),
        );
      }),
    ]);
  }
}

/// The list / table mode's preview: the first items as the file will list them (the server's pages in step 5 are
/// the real thing).
class LayoutItemsPreview extends StatelessWidget {
  const LayoutItemsPreview({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final items = f.items.take(5).toList();
    const ink = Color(0xFF1A1A1A);
    final style = TextStyle(fontFamily: null, fontSize: 12, color: ink, height: 1.3);
    Widget body;
    if (d.mode == 'list') {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${d.list.numbered ? '${i + 1}. ' : ''}${[for (final b in d.list.fields) layoutFormat(items[i][b.field], b, field: f.fieldOf(b.field), lang: f.lang)].join(d.list.separator)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
      ]);
    } else {
      final cols = d.table.columns;
      final total = cols.fold<double>(0, (a, c) => a + c.width);
      TextAlign al(String a) => a == 'center' ? TextAlign.center : (a == 'end' ? TextAlign.end : TextAlign.start);
      Widget cell(String s, String align, {bool head = false}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: al(align), style: head ? style.copyWith(fontWeight: FontWeight.w700) : style),
          );
      body = cols.isEmpty
          ? const SizedBox(height: 24)
          : Table(
              columnWidths: {for (var i = 0; i < cols.length; i++) i: FlexColumnWidth(total <= 0 ? 1 : cols[i].width / total)},
              border: TableBorder.all(color: layoutColor(d.table.borders?.color, const Color(0xFFEAECF0))!, width: .6),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: layoutColor(d.table.headerStyle.bg)),
                  children: [for (final c in cols) cell(c.field.label ?? f.fieldOf(c.field.field)?.label(f.lang) ?? c.field.field, c.align, head: true)],
                ),
                for (var i = 0; i < items.length; i++)
                  TableRow(
                    decoration: BoxDecoration(color: i.isOdd ? layoutColor(d.table.zebra) : null),
                    children: [for (final c in cols) cell(layoutFormat(items[i][c.field.field], c.field, field: f.fieldOf(c.field.field), lang: f.lang), c.align)],
                  ),
              ],
            );
    }
    return Container(
      color: kStudioPaper,
      padding: const EdgeInsets.all(AppSpace.xs),
      child: Directionality(textDirection: d.page.rtl ? TextDirection.rtl : TextDirection.ltr, child: body),
    );
  }
}

/// The list / table field editor: tick the fields, drag to order; a table column also has its width and alignment.
class LayoutFieldsEditor extends StatelessWidget {
  const LayoutFieldsEditor({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final c = context.colors;
    final table = d.mode == 'table';
    final picked = table ? [for (final col in d.table.columns) col.field.field] : [for (final b in d.list.fields) b.field];
    final order = [...picked, for (final x in f.allFields) if (!picked.contains(x.key)) x.key];

    void rebalance() {
      final cols = d.table.columns;
      final sum = cols.fold<double>(0, (a, c) => a + c.width);
      if (sum <= 0) return;
      final k = d.page.contentWidth / sum;
      for (final col in cols) {
        col.width = mm(col.width * k);
      }
    }

    void toggle(String key, bool on) {
      final field = f.fieldOf(key)!;
      if (table) {
        if (on) {
          d.table.columns.add(LayoutColumn(field: field.bind(lang: f.lang), width: d.page.contentWidth / (d.table.columns.length + 1), align: field.numeric ? 'end' : 'start', style: LayoutStyle(size: 9)));
        } else {
          d.table.columns.removeWhere((x) => x.field.field == key);
        }
        rebalance();
      } else {
        on ? d.list.fields.add(field.bind()) : d.list.fields.removeWhere((x) => x.field == key);
      }
      f.changed();
    }

    void reorder(int from, int to) {
      if (from >= picked.length) return;
      to = to.clamp(0, picked.length - 1);
      if (table) {
        final x = d.table.columns.removeAt(from);
        d.table.columns.insert(to, x);
      } else {
        final x = d.list.fields.removeAt(from);
        d.list.fields.insert(to, x);
      }
      f.changed();
    }

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: reorder,
      children: [
        for (var i = 0; i < order.length; i++)
          Container(
            key: ValueKey('layout-field-${order[i]}'),
            margin: const EdgeInsets.only(bottom: AppSpace.xxs),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
            child: Column(children: [
              Row(children: [
                Checkbox(value: i < picked.length, onChanged: (v) => toggle(order[i], v ?? false)),
                Expanded(
                  child: Text(f.fieldOf(order[i])?.label(f.lang) ?? order[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                ),
                if (i < picked.length)
                  ReorderableDragStartListener(
                    index: i,
                    child: SizedBox(width: AppTouch.min, height: AppTouch.min, child: Icon(Icons.drag_indicator_rounded, color: c.textMedium)),
                  ),
              ]),
              if (table && i < picked.length)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
                  child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: 150,
                      child: StudioStepper(
                        label: t('العرض (مم)', 'Width (mm)'),
                        value: d.table.columns[i].width,
                        min: 5,
                        max: d.page.contentWidth,
                        step: 1,
                        onChanged: (v) {
                          d.table.columns[i].width = v;
                          f.changed();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: StudioSegmented<String>(
                        segments: [
                          StudioSegment(value: 'start', label: t('بداية', 'Start')),
                          StudioSegment(value: 'center', label: t('وسط', 'Centre')),
                          StudioSegment(value: 'end', label: t('نهاية', 'End')),
                        ],
                        value: d.table.columns[i].align,
                        onChanged: (v) {
                          d.table.columns[i].align = v;
                          f.changed();
                        },
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}

/// The phone form of the Row Designer: which field each slot of the starter card shows, add / remove fields.
class LayoutCardFieldsEditor extends StatelessWidget {
  const LayoutCardFieldsEditor({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final c = context.colors;
    final slots = [for (final e in d.row.elements) if (e.bind != null) e];
    final opts = layoutFieldOptions(f);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in slots)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(children: [
            Expanded(
              child: AppDropdown<String>(
                value: opts.any((o) => o.key == e.bind!.field) ? e.bind!.field : null,
                decoration: InputDecoration(labelText: layoutKindLabel(e.kind), isDense: true),
                items: [for (final o in opts) DropdownMenuItem(value: o.key, child: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  if (v == null) return;
                  e.bind!.field = v;
                  e.bind!.format = f.fieldOf(v)?.defaultFormat ?? 'text';
                  e.name = f.fieldOf(v)?.label(f.lang);
                  f.changed();
                },
              ),
            ),
            IconButton(
              tooltip: t('إزالة', 'Remove'),
              onPressed: () {
                d.row.elements.remove(e);
                f.changed();
              },
              icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger),
            ),
          ]),
        ),
      OutlinedButton.icon(
        key: const ValueKey('layout-card-add-field'),
        onPressed: opts.isEmpty
            ? null
            : () {
                final used = {for (final e in slots) e.bind!.field};
                final pick = f.allFields.firstWhere((x) => !used.contains(x.key), orElse: () => f.allFields.first);
                final cw = d.row.cardWidth(d.page.contentWidth);
                final y = d.row.height;
                d.row.height = mm(y + 7);
                d.row.elements.add(LayoutElement(
                  id: d.newId('r'),
                  kind: 'field',
                  x: 2.5,
                  y: y,
                  w: cw - 5,
                  h: 5.5,
                  name: pick.label(f.lang),
                  bind: pick.bind(),
                  style: LayoutStyle(size: 9, maxLines: 1),
                ));
                f.changed();
              },
        icon: const Icon(Icons.add_rounded),
        label: Text(t('إضافة حقل', 'Add a field')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
    ]);
  }
}

/// Row options: per line, height, zebra, separator, border, keep together (custom) / numbering (list) / header
/// repeat (table) — then sort, group by and totals for every mode.
class LayoutRowOptions extends StatelessWidget {
  const LayoutRowOptions({super.key, required this.flow, this.rows = true, this.sortGroup = false});
  final LayoutFlowController flow;

  /// Which sections: the rows' look (design step) and / or sort, group and totals (layout step).
  final bool rows, sortGroup;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final row = d.row;
    final c = context.colors;
    final opts = layoutFieldOptions(f);
    void set(VoidCallback fn) {
      fn();
      f.changed();
    }

    Widget fieldDrop(String? value, String label, ValueChanged<String?> onChanged, {bool none = false}) => AppDropdown<String>(
          value: value ?? (none ? '' : null),
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            if (none) DropdownMenuItem(value: '', child: Text(t('بدون', 'None'))),
            for (final o in opts) DropdownMenuItem(value: o.key, child: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged(v == null || v.isEmpty ? null : v),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows && d.mode != 'page') LayoutSection(title: t('شكل الصفوف', 'Rows'), children: [
        if (d.mode == 'custom') ...[
          StudioPropField(
            label: t('البطاقات في السطر', 'Cards per line'),
            child: StudioSegmented<int>(
              segments: const [StudioSegment(value: 1, label: '1'), StudioSegment(value: 2, label: '2'), StudioSegment(value: 3, label: '3'), StudioSegment(value: 4, label: '4')],
              value: row.perLine,
              onChanged: (n) => set(() => layoutSetPerLine(d, n)),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            // a grid that fills the page sizes its cards itself
            if (!row.fillPage)
              SizedBox(width: kLayoutStepperWidth, child: StudioStepper(label: t('ارتفاع البطاقة (مم)', 'Card height (mm)'), value: row.height, min: 4, max: 120, step: .5, decimals: 1, onChanged: (v) => set(() => row.height = v))),
            if (row.perLine > 1)
              SizedBox(width: kLayoutStepperWidth, child: StudioStepper(label: t('المسافة بين البطاقات', 'Gap (mm)'), value: row.gap, min: 0, max: 20, step: .5, decimals: 1, onChanged: (v) => set(() => row.gap = v))),
          ]),
          AppSwitchTile(title: t('ألوان متناوبة', 'Zebra rows'), value: row.zebra != null, onChanged: (v) => set(() => row.zebra = v ? '#F7F9FB' : null)),
          AppSwitchTile(title: t('خط فاصل بين الصفوف', 'Separator line'), value: row.separator != null, onChanged: (v) => set(() => row.separator = v ? LayoutBorder(width: .3, color: '#EAECF0') : null)),
          AppSwitchTile(title: t('إطار للبطاقة', 'Card border'), value: row.border != null, onChanged: (v) => set(() => row.border = v ? LayoutBorder(width: .3, color: '#EAECF0') : null)),
          AppSwitchTile(
            title: t('لا تقسم البطاقة بين صفحتين', 'Keep each card on one page'),
            value: row.keepTogether,
            onChanged: (v) => set(() => row.keepTogether = v),
          ),
        ],
        if (d.mode == 'table') ...[
          AppSwitchTile(title: t('ألوان متناوبة', 'Zebra rows'), value: d.table.zebra != null, onChanged: (v) => set(() => d.table.zebra = v ? '#F7F9FB' : null)),
          AppSwitchTile(title: t('كرر العناوين في كل صفحة', 'Repeat the headings on every page'), value: d.table.repeatHeader, onChanged: (v) => set(() => d.table.repeatHeader = v)),
        ],
        if (d.mode == 'list') ...[
          AppSwitchTile(title: t('ترقيم العناصر', 'Number the items'), value: d.list.numbered, onChanged: (v) => set(() => d.list.numbered = v)),
          StudioTextProp(label: t('الفاصل بين الحقول', 'Between the fields'), value: d.list.separator, onChanged: (v) => set(() => d.list.separator = v)),
        ],
      ]),
      if (sortGroup) LayoutSection(title: t('الترتيب والتجميع', 'Sort and group'), children: [
        fieldDrop(d.sort.isEmpty ? null : d.sort.first.field, t('رتّب حسب', 'Sort by'), (v) => set(() {
              d.sort.clear();
              if (v != null) d.sort.add(LayoutSort(field: v));
            }), none: true),
        if (d.sort.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          StudioSegmented<String>(
            segments: [StudioSegment(value: 'asc', label: t('تصاعدي', 'Ascending')), StudioSegment(value: 'desc', label: t('تنازلي', 'Descending'))],
            value: d.sort.first.dir,
            onChanged: (v) => set(() => d.sort.first.dir = v),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        fieldDrop(d.group?.field, t('جمّع حسب', 'Group by'), (v) => set(() => d.group = v == null ? null : LayoutGroup(field: v, header: d.group?.header, pageBreak: d.group?.pageBreak ?? false, extra: d.group?.extra)), none: true),
        if (d.group != null) ...[
          AppSwitchTile(
            title: t('عنوان لكل مجموعة', 'A heading for each group'),
            value: d.group!.header != null,
            onChanged: (v) => set(() => d.group!.header = v ? layoutGroupHeader(d, f.lang) : null),
          ),
          AppSwitchTile(
            key: const ValueKey('layout-group-page-break'),
            title: t('صفحة جديدة لكل مجموعة', 'A new page for each group'),
            value: d.group!.pageBreak,
            onChanged: (v) => set(() => d.group!.pageBreak = v),
          ),
        ],
      ]),
      if (sortGroup) LayoutSection(
        title: t('المجاميع', 'Totals'),
        trailing: TextButton.icon(
          key: const ValueKey('layout-add-total'),
          onPressed: opts.isEmpty
              ? null
              : () => set(() {
                    final num = f.allFields.where((x) => x.numeric).firstOrNull ?? f.allFields.first;
                    d.totals.add(LayoutTotal(field: num.key, fn: num.numeric ? 'sum' : 'count', label: t('الإجمالي', 'Total')));
                  }),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(t('إضافة', 'Add')),
        ),
        children: [
          if (d.totals.isEmpty) Text(t('بلا مجاميع.', 'No totals.'), style: appText(12.5, c: c.textMedium)),
          for (final tot in d.totals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(width: kLayoutPickWidth, child: fieldDrop(tot.field, t('الحقل', 'Field'), (v) => set(() => tot.field = v ?? tot.field))),
                SizedBox(
                  width: 150,
                  child: AppDropdown<String>(
                    value: tot.fn,
                    decoration: InputDecoration(labelText: t('العملية', 'Function'), isDense: true),
                    items: [for (final fn in LayoutTotal.fns) DropdownMenuItem(value: fn, child: Text(_fnLabel(fn)))],
                    onChanged: (v) => set(() => tot.fn = v ?? 'sum'),
                  ),
                ),
                SizedBox(width: kLayoutLabelWidth, child: StudioTextProp(label: t('العنوان', 'Label'), value: tot.label, onChanged: (v) => set(() => tot.label = v))),
                IconButton(tooltip: t('حذف', 'Remove'), onPressed: () => set(() => d.totals.remove(tot)), icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
              ]),
            ),
        ],
      ),
    ]);
  }

  static String _fnLabel(String fn) => switch (fn) {
        'sum' => t('المجموع', 'Sum'),
        'avg' => t('المتوسط', 'Average'),
        'count' => t('العدد', 'Count'),
        'min' => t('الأصغر', 'Minimum'),
        'max' => t('الأكبر', 'Maximum'),
        _ => fn,
      };
}

/// Sort, group (with "a new page for each group") and totals: the layout step's part of [LayoutRowOptions].
class LayoutSortGroupTotals extends StatelessWidget {
  const LayoutSortGroupTotals({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) => LayoutRowOptions(flow: flow, rows: false, sortGroup: true);
}

/// The group heading band: `{{group}}` in bold at the start side.
LayoutBand layoutGroupHeader(LayoutDesign d, String lang) {
  final w = d.page.contentWidth;
  final e = LayoutElement(id: d.newId('g'), kind: 'text', x: 0, y: 1, w: w, h: 6, value: '{{group}}', name: lang == 'ar' ? 'المجموعة' : 'Group', style: LayoutStyle(size: 11, weight: 700, maxLines: 1));
  return LayoutBand(height: 8, placement: 'flow', elements: [e]);
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Step 4 — the fixed parts
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

String layoutSlotLabel(LayoutBandSlot s) => switch (s) {
      LayoutBandSlot.header => t('رأس الصفحة', 'Header'),
      LayoutBandSlot.beforeItems => t('قبل العناصر', 'Before the items'),
      LayoutBandSlot.afterItems => t('بعد العناصر', 'After the items'),
      LayoutBandSlot.footer => t('تذييل الصفحة', 'Footer'),
    };

String layoutPlacementLabel(String p) => switch (p) {
      'first_page' => t('الصفحة الأولى فقط', 'First page only'),
      'every_page' => t('كل صفحة', 'Every page'),
      'after_items' => t('بعد العناصر مرة واحدة', 'Once, after the items'),
      _ => p,
    };

/// The ready parts a band offers (logos, title, organization, date, filters, page numbers, count, signature,
/// stamp, QR …), placed by the editor.
List<LayoutAddOption> layoutBandAddOptions(LayoutFlowController f) {
  LayoutElement text(String id, String v, String name, {double w = 70, double h = 6, double size = 10, int weight = 400, String color = '#1A1A1A'}) =>
      LayoutElement(id: id, kind: 'text', y: 1, w: w, h: h, value: v, name: name, style: LayoutStyle(size: size, weight: weight, color: color, maxLines: 1));
  return [
    LayoutAddOption(t('شعار', 'Logo'), Icons.image_outlined, (id) => LayoutElement(id: id, kind: 'image', y: 1, w: 18, h: 18, name: t('شعار', 'Logo'), fit: 'contain', style: LayoutStyle(padding: 0))),
    LayoutAddOption(t('العنوان', 'Title'), Icons.title_rounded, (id) => text(id, '{{title}}', t('العنوان', 'Title'), w: 110, h: 9, size: 16, weight: 700)),
    LayoutAddOption(t('عنوان فرعي', 'Subtitle'), Icons.short_text_rounded, (id) => text(id, t('عنوان فرعي', 'Subtitle'), t('عنوان فرعي', 'Subtitle'), w: 100, size: 11, color: '#475467')),
    LayoutAddOption(t('اسم المؤسسة', 'Organization name'), Icons.apartment_rounded, (id) => text(id, '{{org_name}}', t('اسم المؤسسة', 'Organization'))),
    LayoutAddOption(t('التاريخ', 'Date'), Icons.event_rounded, (id) => text(id, '{{date}}', t('التاريخ', 'Date'), w: 40, size: 9, color: '#475467')),
    LayoutAddOption(t('عوامل التصفية', 'Filters'), Icons.filter_alt_outlined, (id) => text(id, '{{filters}}', t('عوامل التصفية', 'Filters'), w: 120, size: 8.5, color: '#667085')),
    LayoutAddOption(t('أرقام الصفحات', 'Page numbers'), Icons.numbers_rounded,
        (id) => LayoutElement(id: id, kind: 'page_number', y: 1, w: 35, h: 5, value: '{{page}} / {{pages}}', name: t('رقم الصفحة', 'Page number'), style: LayoutStyle(size: 8, color: '#667085', align: 'center', maxLines: 1))),
    LayoutAddOption(t('العدد الكلي', 'Total count'), Icons.functions_rounded, (id) => text(id, t('العدد: {{total}}', 'Items: {{total}}'), t('العدد الكلي', 'Total count'), w: 40, size: 9)),
    LayoutAddOption(t('المُصدِّر', 'Exported by'), Icons.person_outline_rounded, (id) => text(id, '{{exporter}}', t('المُصدِّر', 'Exported by'), w: 60, size: 8, color: '#667085')),
    LayoutAddOption(t('توقيع', 'Signature'), Icons.draw_rounded,
        (id) => LayoutElement(id: id, kind: 'signature', y: 1, w: 45, h: 22, name: t('توقيع', 'Signature'), fit: 'contain', sigName: t('الاسم', 'Name'), sigTitle: t('الصفة', 'Title'), style: LayoutStyle(size: 9, align: 'center'))),
    LayoutAddOption(t('ختم', 'Stamp'), Icons.verified_outlined, (id) => LayoutElement(id: id, kind: 'image', y: 1, w: 25, h: 25, name: t('ختم', 'Stamp'), fit: 'contain', style: LayoutStyle(padding: 0))),
    LayoutAddOption(t('رمز QR', 'QR code'), Icons.qr_code_2_rounded, (id) => LayoutElement(id: id, kind: 'qr', y: 1, w: 18, h: 18, value: '{{title}} {{date}}', name: t('رمز QR', 'QR code'), style: LayoutStyle(padding: 0))),
    LayoutAddOption(t('نص', 'Text'), Icons.text_fields_rounded, (id) => text(id, t('نص', 'Text'), t('نص', 'Text'))),
    LayoutAddOption(t('خط', 'Line'), Icons.horizontal_rule_rounded,
        (id) => LayoutElement(id: id, kind: 'line', y: 1, w: 120, h: 1, name: t('خط', 'Line'), style: LayoutStyle(border: LayoutBorder(width: .4, color: '#D0D5DD')))),
    layoutEllipseAddOption(),
  ];
}

/// One fixed part (header / before the items / after the items / footer) on the canvas engine, with its switch,
/// placement and height; the simple list form on phones.
class LayoutBandPart extends StatelessWidget {
  const LayoutBandPart({super.key, required this.flow, required this.slot, required this.width});
  final LayoutFlowController flow;
  final LayoutBandSlot slot;
  final double width;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final canvas = width >= kLayoutCanvasMin;
    final band = d.band(slot);
    final enabled = band != null && (band.height > 0 || band.elements.isNotEmpty);
    final head = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: kLayoutSwitchWidth,
          child: AppSwitchTile(
            key: ValueKey('layout-band-on-${slot.key}'),
            title: t('إظهار هذا الجزء', 'Show this part'),
            value: enabled,
            dense: true,
            onChanged: (v) {
              d.setBand(slot, v ? layoutEmptyBand(slot) : null);
              f.changed();
            },
          ),
        ),
        if (enabled && slot.placements.isNotEmpty)
          SizedBox(
            width: kLayoutPlacementWidth,
            child: AppDropdown<String>(
              value: slot.placements.contains(band.placement) ? band.placement : slot.placements.first,
              decoration: InputDecoration(labelText: t('أين يظهر', 'Where it shows'), isDense: true),
              items: [for (final p in slot.placements) DropdownMenuItem(value: p, child: Text(layoutPlacementLabel(p)))],
              onChanged: (v) {
                band.placement = v ?? band.placement;
                f.changed();
              },
            ),
          ),
        if (enabled)
          SizedBox(
            width: 170,
            child: StudioStepper(label: t('الارتفاع (مم)', 'Height (mm)'), value: band.height, min: 4, max: 120, step: 1, onChanged: (v) {
              band.height = v;
              f.changed();
            }),
          ),
      ]),
    ]);
    if (!enabled) {
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        head,
        const SizedBox(height: AppSpace.lg),
        AppEmpty(
          icon: Icons.view_agenda_outlined,
          title: t('هذا الجزء مخفي', 'This part is hidden'),
          message: t('شغّله لتضيف شعارًا أو عنوانًا أو توقيعًا…', 'Switch it on to add a logo, a title, a signature…'),
        ),
      ]);
    }
    if (!canvas) {
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [head, const SizedBox(height: AppSpace.sm), LayoutBandSimple(flow: f, band: band)]);
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        const SizedBox(height: AppSpace.sm),
        Expanded(
          child: LayoutCanvasEditor(
            key: ValueKey('band-${slot.key}-${f.lang}'),
            elements: band.elements,
            width: d.page.contentWidth,
            height: band.height,
            rtl: d.page.rtl,
            pageFont: d.page.font,
            pageFontSize: d.page.fontSize,
            lang: f.lang,
            fields: layoutFieldOptions(f),
            addOptions: layoutBandAddOptions(f),
            newId: () => d.newId(),
            onChanged: f.changed,
            upload: (b, n) => layoutUpload(f, b, n),
            vars: f.varsFor(f.lang),
            fieldOf: f.fieldOf,
            background: band.background,
            wide: width >= kLayoutDockMin,
          ),
        ),
      ]),
    );
  }
}

/// A band switched on: the footer starts with page numbers, the others empty.
LayoutBand layoutEmptyBand(LayoutBandSlot s) => switch (s) {
      LayoutBandSlot.header => LayoutBand(height: 20, placement: 'first_page'),
      LayoutBandSlot.footer => LayoutBand(height: 9, placement: 'every_page'),
      _ => LayoutBand(height: 14, placement: 'flow'),
    };

/// The phone form of a band: its parts as a list (remove), and the ready parts to add (stacked under the last).
class LayoutBandSimple extends StatelessWidget {
  const LayoutBandSimple({super.key, required this.flow, required this.band});
  final LayoutFlowController flow;
  final LayoutBand band;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final c = context.colors;
    final w = d.page.contentWidth;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: kStudioPaper,
        padding: const EdgeInsets.all(AppSpace.xxs),
        child: LayoutBuilder(builder: (context, box) {
          final s = box.maxWidth / w;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: LayoutBoxView(elements: band.elements, width: w, height: band.height, scale: s, rtl: d.page.rtl, pageFont: d.page.font, pageFontSize: d.page.fontSize, lang: f.lang, vars: f.varsFor(f.lang), fieldOf: f.fieldOf, background: band.background),
          );
        }),
      ),
      const SizedBox(height: AppSpace.sm),
      for (final e in band.elements)
        Container(
          margin: const EdgeInsets.only(bottom: AppSpace.xxs),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
          child: Row(children: [
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(e.name ?? layoutKindLabel(e.kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark))),
            IconButton(
              tooltip: t('إزالة', 'Remove'),
              onPressed: () {
                band.elements.remove(e);
                f.changed();
              },
              icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger),
            ),
          ]),
        ),
      const SizedBox(height: AppSpace.xs),
      Text(t('أضف', 'Add'), style: appText(13, w: FontWeight.w600, c: c.textMedium)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final o in layoutBandAddOptions(f))
          ActionChip(
            avatar: Icon(o.icon, size: 18),
            label: Text(o.label),
            onPressed: () {
              final e = o.build(d.newId());
              final bottom = band.elements.fold<double>(0, (a, x) => x.y + x.h > a ? x.y + x.h : a);
              e.w = e.w.clamp(2, w).toDouble();
              e.x = d.page.rtl ? w - e.w : 0;
              e.y = bottom + (band.elements.isEmpty ? 1 : .5);
              if (e.y + e.h > band.height) band.height = mm(e.y + e.h + 1);
              band.elements.add(e);
              f.changed();
            },
          ),
      ]),
    ]);
  }
}

/// The page: size, orientation, margins, font, frame, watermark.
class LayoutPageOptions extends StatelessWidget {
  const LayoutPageOptions({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final d = f.design;
    final p = d.page;
    void set(VoidCallback fn) {
      fn();
      f.changed();
    }

    final fonts = [
      for (final x in f.fonts) StudioFontOption(id: x.id, label: x.label(f.lang)),
      if (!f.fonts.any((x) => x.id == p.font)) StudioFontOption(id: p.font, label: p.font),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutSection(title: t('الورق', 'Paper'), children: [
        StudioSegmented<String>(
          segments: [for (final s in LayoutPage.sizes.keys) StudioSegment(value: s, label: s)],
          value: p.size,
          onChanged: (v) => set(() => layoutSetPage(d, (p) => p.size = v)),
        ),
        const SizedBox(height: AppSpace.xs),
        StudioSegmented<String>(
          segments: [StudioSegment(value: 'portrait', label: t('طولي', 'Portrait')), StudioSegment(value: 'landscape', label: t('عرضي', 'Landscape'))],
          value: p.orientation,
          onChanged: (v) => set(() => layoutSetPage(d, (p) => p.orientation = v)),
        ),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
          for (final (label, get, put) in [
            (t('أعلى', 'Top'), () => p.margins.top, (double v) => p.margins.top = v),
            (t('أسفل', 'Bottom'), () => p.margins.bottom, (double v) => p.margins.bottom = v),
            (t('يمين', 'Right'), () => p.margins.right, (double v) => p.margins.right = v),
            (t('يسار', 'Left'), () => p.margins.left, (double v) => p.margins.left = v),
          ])
            SizedBox(width: kLayoutMarginWidth, child: StudioStepper(label: '$label (mm)', value: get(), min: 0, max: 60, step: 1, onChanged: (v) => set(() => layoutSetPage(d, (_) => put(v))))),
        ]),
      ]),
      LayoutSection(title: t('الخط', 'Font'), children: [
        StudioFontPicker(options: fonts, value: p.font, onChanged: (v) => set(() => p.font = v)),
        const SizedBox(height: AppSpace.xs),
        StudioStepper(label: t('حجم النص (pt)', 'Text size (pt)'), value: p.fontSize, min: 6, max: 24, step: .5, decimals: 1, onChanged: (v) => set(() => p.fontSize = v)),
      ]),
      LayoutSection(title: t('الإطار والعلامة المائية', 'Frame and watermark'), children: [
        AppSwitchTile(title: t('إطار حول الصفحة', 'A frame around the page'), value: d.frame != null, onChanged: (v) => set(() => d.frame = v ? LayoutBorder(width: .5, color: '#98A2B3') : null)),
        AppSwitchTile(
          key: const ValueKey('layout-watermark'),
          title: t('علامة مائية', 'Watermark'),
          value: d.watermark != null,
          onChanged: (v) => set(() => d.watermark = v ? LayoutWatermark(text: f.lang == 'ar' ? 'سري' : 'CONFIDENTIAL') : null),
        ),
        if (d.watermark != null) ...[
          StudioTextProp(label: t('نص العلامة', 'Watermark text'), value: d.watermark!.text, onChanged: (v) => set(() => d.watermark!.text = v)),
          const SizedBox(height: AppSpace.xs),
          StudioOpacitySlider(label: t('الشفافية', 'Opacity'), value: d.watermark!.opacity, onChanged: (v) => set(() => d.watermark!.opacity = v)),
        ],
      ]),
    ]);
  }
}


// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Preview + export
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class LayoutPreviewStep extends StatelessWidget {
  const LayoutPreviewStep({super.key, required this.flow, required this.width, required this.onSaveTemplate, this.onSaveDesign});
  final LayoutFlowController flow;
  final double width;
  final VoidCallback onSaveTemplate;

  /// A design-only page: "Save the design" instead of Export.
  final VoidCallback? onSaveDesign;

  @override
  Widget build(BuildContext context) {
    final pages = LayoutPreviewPages(flow: flow);
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutExportCard(flow: flow, onSaveTemplate: onSaveTemplate, onSaveDesign: onSaveDesign),
      LayoutIssuesCard(issues: flow.issues),
    ]);
    if (width >= kLayoutDockMin) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: pages),
          const SizedBox(width: AppSpace.md),
          SizedBox(width: kLayoutPreviewSide, child: ListView(children: [side])),
        ]),
      );
    }
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [SizedBox(height: kLayoutPreviewHeight, child: pages), const SizedBox(height: AppSpace.md), side]);
  }
}

/// The server's pages of the current language: previous / next, refresh. While a new preview is made the old pages
/// stay (with a thin progress line), and the page the person is on is kept; an error over an old preview is a banner,
/// not a blank.
class LayoutPreviewPages extends StatelessWidget {
  const LayoutPreviewPages({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final c = context.colors;
    final p = f.preview;
    Widget frame(Widget child) => Container(
          decoration: BoxDecoration(color: c.background, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
    if (f.previewLoading && p == null) {
      return frame(AppShimmer(
        child: Center(
          child: AspectRatio(aspectRatio: f.design.page.width / f.design.page.height, child: const Padding(padding: EdgeInsets.all(AppSpace.lg), child: AppSkeletonBox(width: double.infinity, height: double.infinity))),
        ),
      ));
    }
    if (p == null) {
      return frame(Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: AppEmpty(
            icon: f.previewMissing ? Icons.system_update_alt_rounded : Icons.image_not_supported_outlined,
            title: f.previewMissing ? t('المعاينة تحتاج تحديث الخادم', 'The preview needs a server update') : (f.previewError == null ? t('المعاينة قيد التجهيز', 'Preparing the preview') : t('تعذّرت المعاينة', 'Could not show the preview')),
            message: f.previewError,
            actionLabel: t('إعادة المحاولة', 'Retry'),
            onAction: f.refreshPreview,
          ),
        ),
      ));
    }
    if (p.pages.isEmpty) {
      return frame(Center(child: AppEmpty(icon: Icons.description_outlined, title: t('لا صفحات', 'No pages'), actionLabel: t('تحديث', 'Refresh'), onAction: f.refreshPreview)));
    }
    final i = f.previewPage.clamp(0, p.pages.length - 1);
    final page = p.pages[i];
    return frame(Column(children: [
      if (f.previewLoading) LinearProgressIndicator(minHeight: 2, backgroundColor: c.divider, color: c.primary),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: Row(children: [
          IconButton(tooltip: t('الصفحة السابقة', 'Previous page'), onPressed: i > 0 ? () => f.showPreviewPage(i - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Text(
              '${t('صفحة', 'Page')} ${page.index} ${t('من', 'of')} ${page.total}',
              key: const ValueKey('layout-page-label'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(13, w: FontWeight.w600, c: c.textDark),
            ),
          ),
          IconButton(tooltip: t('الصفحة التالية', 'Next page'), onPressed: i < p.pages.length - 1 ? () => f.showPreviewPage(i + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
          IconButton(tooltip: t('تحديث المعاينة', 'Refresh the preview'), onPressed: f.refreshPreview, icon: const Icon(Icons.refresh_rounded)),
        ]),
      ),
      if (f.previewError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, AppSpace.xs, AppSpace.xs),
          child: AppBanner(icon: Icons.error_outline_rounded, text: f.previewError!, color: c.danger),
        ),
      Expanded(
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(child: Padding(padding: const EdgeInsets.all(AppSpace.sm), child: Image.memory(page.png, fit: BoxFit.contain, gaplessPlayback: true))),
        ),
      ),
    ]));
  }
}

/// The server's notes for the current design, one per line (no card around them).
class LayoutIssuesList extends StatelessWidget {
  const LayoutIssuesList({super.key, required this.issues});
  final List<LayoutIssue> issues;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = AppConfig.lang;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final i in issues)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              i.severity == 'error' ? Icons.error_outline_rounded : (i.severity == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline_rounded),
              size: 18,
              color: i.severity == 'error' ? c.danger : c.textMedium,
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(i.message(lang), style: appText(12.5, c: c.textDark))),
          ]),
        ),
    ]);
  }
}

class LayoutIssuesCard extends StatelessWidget {
  const LayoutIssuesCard({super.key, required this.issues});
  final List<LayoutIssue> issues;

  @override
  Widget build(BuildContext context) => LayoutSection(
        title: t('ملاحظات', 'Notes'),
        subtitle: issues.isEmpty ? t('لا ملاحظات: الملف سيطابق المعاينة.', 'No notes: the file will match the preview.') : null,
        children: [LayoutIssuesList(issues: issues)],
      );
}

class LayoutExportCard extends StatelessWidget {
  const LayoutExportCard({super.key, required this.flow, required this.onSaveTemplate, this.onSaveDesign});
  final LayoutFlowController flow;
  final VoidCallback onSaveTemplate;
  final VoidCallback? onSaveDesign;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final phase = f.phase;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (onSaveDesign == null) ...[
        if (f.isXlsx) const Padding(padding: EdgeInsets.only(bottom: AppSpace.md), child: LayoutExcelNote()),
        LayoutRunPanel(flow: f),
        if (!f.busy)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppPrimaryButton(
              key: const ValueKey('layout-run-start'),
              label: phase == LayoutRunPhase.done ? t('تصدير مرة أخرى', 'Export again') : t('تصدير', 'Export'),
              icon: Icons.file_download_outlined,
              onPressed: () => f.startRun(),
            ),
          ),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppPrimaryButton(key: const ValueKey('layout-save-design'), label: t('حفظ التصميم', 'Save the design'), icon: Icons.check_rounded, onPressed: onSaveDesign),
        ),
      OutlinedButton.icon(
        key: const ValueKey('layout-save-template'),
        onPressed: onSaveTemplate,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(t('حفظ كقالب', 'Save as a template')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
      const SizedBox(height: AppSpace.md),
    ]);
  }
}
