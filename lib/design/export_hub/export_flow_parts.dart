// lib/design/export_hub/export_flow_parts.dart
//
// The export flow's presentational parts — plain values in, callbacks out, so the layout harness pumps each one
// (test/ui/export_studio_layout_test.dart):
//
//   ExportFlowStepper     Format · Fields · Language · Design · Export (labels on wide, "Step 2 of 5" on phones)
//   ExportFormatCard      Excel / Word / PDF with a one-line hint
//   ExportFieldPicker     the fields checklist: search, all / none, drag to reorder, rename per language, locked
//   ExportLanguagePicker  Arabic · English · Both, and Arabic-Indic vs Western digits
//   ExportThemeCard       a starter theme with its thumbnail
//   ExportRuleBuilder     field · condition · value · style (colour, background, bold, label, hide the row)
//   ExportSheetPreview    the Excel sheet as it will open: column letters, title band, header, rows, rules
//   ExportSummaryLine     one "label · value" row of the last step
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_contrast.dart';
import '../app_kit.dart';
import '../app_tokens.dart';
import '../export/export_studio_model.dart';
import '../export/table_export_choice.dart';
import '../export/table_export_model.dart';
import '../studio/studio_props.dart' show StudioColorField, StudioSegment, StudioSegmented, kStudioSwatches, studioHex;
import 'export_designer.dart' show exportColor, exportFlutterFont;

/// The sheet preview draws in the document font (an embedded document font, not the UI font).
final _sheetFont = exportFlutterFont('');

String xs(String key, String en, String ar) => tx(key, en, ar);

IconData exportFormatIconOf(AppExportFormat f) => switch (f) {
      AppExportFormat.xlsx => Icons.grid_on_rounded,
      AppExportFormat.docx => Icons.description_rounded,
      AppExportFormat.pdf => Icons.picture_as_pdf_rounded,
    };

String exportFormatName(AppExportFormat f) => switch (f) { AppExportFormat.xlsx => 'Excel', AppExportFormat.docx => 'Word', AppExportFormat.pdf => 'PDF' };

IconData exportColumnIcon(AppColType t) => switch (t) {
      AppColType.text => Icons.short_text_rounded,
      AppColType.number || AppColType.integer => Icons.tag_rounded,
      AppColType.money => Icons.payments_outlined,
      AppColType.percent => Icons.percent_rounded,
      AppColType.date || AppColType.dateTime => Icons.event_rounded,
      AppColType.status => Icons.label_outline_rounded,
    };

String exportLangName(String l) => switch (l) {
      'ar' => 'العربية',
      'en' => 'English',
      _ => xs('exs_lang_both', 'Both', 'كلتاهما'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Stepper
// ═════════════════════════════════════════════════════════════════════════════

class ExportFlowStepper extends StatelessWidget {
  const ExportFlowStepper({super.key, required this.labels, required this.current, required this.reached, required this.onTap, this.compact = false});

  final List<String> labels;
  final int current, reached;
  final ValueChanged<int> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    if (compact) {
      return Semantics(
        label: '${xs('exs_step_of', 'Step', 'الخطوة')} ${current + 1} / ${labels.length}: ${labels[current]}',
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('${current + 1} / ${labels.length}', style: appText(12.5, w: FontWeight.w600, c: accent)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(labels[current], maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark))),
          ]),
          const SizedBox(height: AppSpace.xs),
          Row(children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.xxs),
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.of(context).base,
                  height: 4,
                  decoration: BoxDecoration(color: i <= current ? c.primary : c.divider, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ]),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      // every label when they fit (≈ 110 px a step at the current text size), else only the current one
      final all = box.maxWidth >= labels.length * MediaQuery.textScalerOf(context).scale(110);
      return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) Expanded(child: Container(height: 1.5, margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), color: i <= reached ? c.primary.withValues(alpha: .5) : c.divider)),
        Semantics(
          button: true,
          selected: i == current,
          enabled: i <= reached,
          label: labels[i],
          excludeSemantics: true,
          child: InkWell(
            onTap: i <= reached && i != current ? () => onTap(i) : null,
            borderRadius: AppRadius.chipAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: AppMotion.of(context).base,
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == current ? c.primary : (i < current ? c.primaryTint : Colors.transparent),
                      border: Border.all(color: i <= reached ? c.primary : c.divider, width: 1.5),
                    ),
                    child: i < current
                        ? Icon(Icons.check_rounded, size: 14, color: accent)
                        : Text('${i + 1}', style: appText(11.5, w: FontWeight.w600, c: i == current ? Theme.of(context).colorScheme.onPrimary : c.textMedium)),
                  ),
                  if (all || i == current) ...[
                    const SizedBox(width: AppSpace.xxs + 2),
                    Text(labels[i], style: appText(12.5, w: i == current ? FontWeight.w600 : FontWeight.w500, c: i == current ? c.textDark : c.textMedium)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Format card
// ═════════════════════════════════════════════════════════════════════════════

class ExportFormatCard extends StatelessWidget {
  const ExportFormatCard({super.key, required this.format, required this.selected, required this.onTap});
  final AppExportFormat format;
  final bool selected;
  final VoidCallback? onTap;

  static Color tone(AppExportFormat f) => switch (f) {
        AppExportFormat.xlsx => const Color(0xFF1D7044),
        AppExportFormat.docx => const Color(0xFF2B5797),
        AppExportFormat.pdf => const Color(0xFFC0392B),
      };

  static String hint(AppExportFormat f) => switch (f) {
        AppExportFormat.xlsx => xs('exs_fmt_xlsx_hint', 'Sort, filter and calculate', 'فرز وتصفية وحساب'),
        AppExportFormat.docx => xs('exs_fmt_docx_hint', 'Edit the document', 'مستند قابل للتعديل'),
        AppExportFormat.pdf => xs('exs_fmt_pdf_hint', 'Ready to print and send', 'جاهز للطباعة والإرسال'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tone(format);
    final ink = ensureContrast(t, [c.cardBg, Color.alphaBlend(t.withValues(alpha: .14), c.cardBg)]);
    return Semantics(
      button: true,
      selected: selected,
      label: '${exportFormatName(format)} — ${hint(format)}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardAll,
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
            constraints: const BoxConstraints(minHeight: 112),
            decoration: BoxDecoration(
              color: selected ? c.primaryTint : c.cardBg,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.withValues(alpha: .14), borderRadius: AppRadius.chipAll),
                child: Icon(exportFormatIconOf(format), color: ink, size: 22),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(exportFormatName(format), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
              const SizedBox(height: 2),
              Text(hint(format), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: appText(11.5, w: FontWeight.w400, c: c.textMedium)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Fields
// ═════════════════════════════════════════════════════════════════════════════

/// The fields checklist. Mutates [choice] and calls [onChanged] after every change. [lang] is the language whose
/// headers are shown (the other one is edited in the rename sheet).
class ExportFieldPicker extends StatefulWidget {
  const ExportFieldPicker({super.key, required this.export, required this.choice, required this.lang, required this.onChanged, this.shrinkWrap = true});
  final AppTableExport export;
  final AppExportChoice choice;
  final String lang;
  final VoidCallback onChanged;
  final bool shrinkWrap;

  @override
  State<ExportFieldPicker> createState() => _ExportFieldPickerState();
}

class _ExportFieldPickerState extends State<ExportFieldPicker> {
  final _search = TextEditingController();
  String _q = '';

  AppTableExport get e => widget.export;
  AppExportChoice get ch => widget.choice;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = ch.order.length;
    final picked = ch.order.where((id) => ch.selected.contains(id) || (e.column(id)?.locked ?? false)).length;
    final searching = _q.isNotEmpty;
    final ids = searching
        ? ch.order.where((id) {
            final col = e.column(id);
            return col != null && (ch.labelOf(col, 'ar').toLowerCase().contains(_q) || ch.labelOf(col, 'en').toLowerCase().contains(_q) || col.label.toLowerCase().contains(_q));
          }).toList()
        : ch.order;
    final group = ch.groupByFor(e);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, runSpacing: AppSpace.xxs, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          // the editorial section face is wide at text ×1.3: the title gives way, never the count
          Flexible(child: Text(xs('exs_fields_n', 'Fields', 'الحقول'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
          const SizedBox(width: AppSpace.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(20)),
            child: Text('$picked / $total', style: appText(12, w: FontWeight.w600, c: ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)]))),
          ),
        ]),
        if (e.allowColumnSelection)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (label, on) in [(xs('exs_all', 'All', 'الكل'), true), (xs('exs_none', 'None', 'لا شيء'), false)])
              TextButton(
                onPressed: () => _changed(() => ch.setAll(e, on)),
                style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
                child: Text(label),
              ),
          ]),
      ]),
      Text(xs('exs_fields_hint', 'Tick what to export, drag to reorder, rename a header for each language.', 'اختر ما يُصدَّر، واسحب لترتيبه، وأعد تسمية العنوان لكل لغة.'),
          style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      if (total > 8)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            style: appText(14, c: c.textDark),
            decoration: InputDecoration(
              isDense: true,
              hintText: xs('exs_search_fields', 'Search fields', 'ابحث في الحقول'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: xs('exs_clear', 'Clear', 'مسح'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() {
                        _search.clear();
                        _q = '';
                      }),
                    ),
            ),
          ),
        ),
      if (ids.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Text(xs('exs_no_field_match', 'No field matches', 'لا يوجد حقل مطابق'), textAlign: TextAlign.center, style: AppType.meta(context)),
        )
      else
        Container(
          decoration: BoxDecoration(border: Border.all(color: c.divider), borderRadius: AppRadius.cardAll),
          clipBehavior: Clip.antiAlias,
          child: searching
              ? ListView.builder(
                  shrinkWrap: widget.shrinkWrap,
                  physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
                  padding: EdgeInsets.zero,
                  itemCount: ids.length,
                  itemBuilder: (_, i) => _tile(context, ids, i, false, group),
                )
              : ReorderableListView.builder(
                  shrinkWrap: widget.shrinkWrap,
                  physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
                  padding: EdgeInsets.zero,
                  buildDefaultDragHandles: false,
                  itemCount: ids.length,
                  proxyDecorator: (child, _, _) => Material(color: c.cardBg, elevation: 4, borderRadius: AppRadius.chipAll, child: child),
                  onReorderItem: (from, to) => _changed(() => ch.move(from, to > from ? to + 1 : to)),
                  itemBuilder: (_, i) => _tile(context, ids, i, ids.length > 1, group),
                ),
        ),
    ]);
  }

  Widget _tile(BuildContext context, List<String> ids, int i, bool reorderable, String? group) {
    final c = context.colors;
    final col = e.column(ids[i])!;
    final on = ch.selected.contains(col.id) || col.locked;
    final heads = col.id == group;
    final label = ch.labelOf(col, widget.lang);
    return Material(
      key: ValueKey(col.id),
      color: c.cardBg,
      child: InkWell(
        onTap: col.locked || !e.allowColumnSelection
            ? null
            : () => _changed(() {
                  if (!ch.selected.remove(col.id)) ch.selected.add(col.id);
                }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, end: AppSpace.xxs),
          decoration: BoxDecoration(border: i == ids.length - 1 ? null : Border(bottom: BorderSide(color: c.divider.withValues(alpha: .6)))),
          child: Row(children: [
            if (reorderable)
              ReorderableDragStartListener(
                index: i,
                child: Tooltip(
                  message: xs('exs_drag', 'Drag to reorder', 'اسحب للترتيب'),
                  child: SizedBox(width: 40, height: AppTouch.min, child: Icon(Icons.drag_indicator_rounded, size: 20, color: c.textLight)),
                ),
              )
            else
              const SizedBox(width: AppSpace.xs),
            Semantics(
              checked: on,
              label: label,
              child: Checkbox(
                value: on,
                onChanged: col.locked || !e.allowColumnSelection
                    ? null
                    : (v) => _changed(() {
                          if (v == true) {
                            ch.selected.add(col.id);
                          } else {
                            ch.selected.remove(col.id);
                          }
                        }),
              ),
            ),
            Icon(exportColumnIcon(col.type), size: 18, color: on ? c.textMedium : c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: on ? FontWeight.w500 : FontWeight.w400, c: on ? c.textDark : c.textMedium)),
                if (col.locked || heads || ch.renamed(col.id))
                  Text(
                    [
                      if (col.locked) xs('exs_always', 'Always exported', 'يُصدَّر دائمًا'),
                      if (heads) xs('exs_heads_groups', 'Heads each group', 'عنوان كل مجموعة'),
                      if (ch.renamed(col.id)) '${xs('exs_renamed', 'Renamed', 'أُعيدت تسميته')} · ${col.label}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(11.5, w: FontWeight.w400, c: c.textMedium),
                  ),
              ]),
            ),
            IconButton(
              tooltip: xs('exs_rename', 'Rename', 'إعادة تسمية'),
              onPressed: () async {
                if (await showExportRenameSheet(context, col, ch)) _changed(() {});
              },
              icon: Icon(Icons.edit_outlined, size: 20, color: c.textMedium),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Rename one header in both languages. True when something changed.
Future<bool> showExportRenameSheet(BuildContext context, AppExportColumn col, AppExportChoice ch) async {
  final ar = TextEditingController(text: ch.labelOf(col, 'ar'));
  final en = TextEditingController(text: ch.labelOf(col, 'en'));
  final ok = await showAppSheet<bool>(
    context,
    (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(xs('exs_rename_title', 'Rename the header', 'إعادة تسمية العنوان')),
          Text(xs('exs_rename_hint', 'Each language prints its own header. Leave a field empty to use the original.', 'لكل لغة عنوانها في الملف. اترك الحقل فارغًا لاستخدام الأصلي.'),
              style: AppType.meta(ctx)),
          const SizedBox(height: AppSpace.sm),
          Directionality(
            textDirection: TextDirection.rtl,
            child: TextField(controller: ar, maxLength: 120, decoration: InputDecoration(labelText: 'العربية', hintText: col.labelIn('ar'), counterText: '')),
          ),
          const SizedBox(height: AppSpace.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(controller: en, maxLength: 120, decoration: InputDecoration(labelText: 'English', hintText: col.labelIn('en'), counterText: '')),
          ),
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(label: xs('exs_save', 'Save', 'حفظ'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, true)),
          TextButton(
            onPressed: () {
              ar.text = col.labelIn('ar');
              en.text = col.labelIn('en');
            },
            child: Text(xs('exs_reset_names', 'Use the original names', 'استخدام الأسماء الأصلية')),
          ),
        ]),
      ),
    ),
  );
  if (ok == true) {
    ch
      ..rename(col, 'ar', ar.text)
      ..rename(col, 'en', en.text);
  }
  ar.dispose();
  en.dispose();
  return ok == true;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Language
// ═════════════════════════════════════════════════════════════════════════════

class ExportLanguagePicker extends StatelessWidget {
  const ExportLanguagePicker({super.key, required this.export, required this.choice, required this.onChanged});
  final AppTableExport export;
  final AppExportChoice choice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option(String id, String title, String sub, IconData icon) {
      final sel = choice.lang == id;
      return Semantics(
        button: true,
        selected: sel,
        label: '$title — $sub',
        excludeSemantics: true,
        child: InkWell(
          onTap: () {
            choice.lang = id;
            onChanged();
          },
          borderRadius: AppRadius.cardAll,
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            padding: const EdgeInsets.all(AppSpace.sm),
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            decoration: BoxDecoration(
              color: sel ? c.primaryTint : c.cardBg,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: sel ? c.primary : c.divider, width: sel ? 1.6 : 1),
            ),
            child: Row(children: [
              Icon(icon, color: sel ? ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)]) : c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w400, c: c.textMedium)),
                ]),
              ),
              if (sel) Icon(Icons.check_circle_rounded, color: ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)]), size: 22),
            ]),
          ),
        ),
      );
    }

    final heads = [for (final id in choice.columns.take(3)) if (export.column(id) != null) export.column(id)!];
    String sample(String l) => heads.map((col) => choice.labelOf(col, l)).join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      option('ar', 'العربية', sample('ar').isEmpty ? xs('exs_lang_ar_sub', 'Right to left', 'من اليمين إلى اليسار') : sample('ar'), Icons.format_textdirection_r_to_l_rounded),
      const SizedBox(height: AppSpace.xs),
      option('en', 'English', sample('en').isEmpty ? xs('exs_lang_en_sub', 'Left to right', 'من اليسار إلى اليمين') : sample('en'), Icons.format_textdirection_l_to_r_rounded),
      const SizedBox(height: AppSpace.xs),
      option('both', xs('exs_lang_both_title', 'Both — two files', 'كلتاهما — ملفان'),
          xs('exs_lang_both_sub', 'Each language with its own design and headers', 'لكل لغة تصميمها وعناوينها'), Icons.translate_rounded),
      if (choice.languages.contains('ar')) ...[
        const SizedBox(height: AppSpace.md),
        Text(xs('exs_digits', 'Digits in the Arabic file', 'الأرقام في الملف العربي'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        StudioSegmented<String>(
          segments: [
            StudioSegment(value: 'western', label: xs('exs_digits_western', 'Western 123', 'غربية 123')),
            StudioSegment(value: 'arabic', label: xs('exs_digits_arabic', 'Arabic ١٢٣', 'عربية ١٢٣')),
          ],
          value: choice.numeralsFor('ar').name,
          onChanged: (v) {
            choice.numerals['ar'] = v;
            onChanged();
          },
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(xs('exs_digits_hint', 'Excel keeps numbers as numbers so they still add up.', 'يحتفظ Excel بالأرقام أرقامًا لتبقى قابلة للحساب.'), style: AppType.meta(context)),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Theme card
// ═════════════════════════════════════════════════════════════════════════════

class ExportThemeCard extends StatelessWidget {
  const ExportThemeCard({super.key, required this.title, required this.hint, required this.selected, required this.onTap, required this.thumbnail});
  final String title, hint;
  final bool selected;
  final VoidCallback onTap;
  final Widget thumbnail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title — $hint',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          padding: const EdgeInsets.all(AppSpace.xs),
          decoration: BoxDecoration(
            color: selected ? c.primaryTint : c.cardBg,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 96, child: ClipRRect(borderRadius: AppRadius.chipAll, child: ColoredBox(color: c.background, child: Padding(padding: const EdgeInsets.all(AppSpace.xxs), child: thumbnail)))),
            const SizedBox(height: AppSpace.xs),
            Row(children: [
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark))),
              if (selected) Icon(Icons.check_circle_rounded, size: 18, color: ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)])),
            ]),
            Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w400, c: c.textMedium)),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rule builder
// ═════════════════════════════════════════════════════════════════════════════

String exportRuleOpLabel(ExportRuleOp op) => switch (op) {
      ExportRuleOp.eq => xs('exs_op_eq', '= equals', '= يساوي'),
      ExportRuleOp.ne => xs('exs_op_ne', '≠ is not', '≠ لا يساوي'),
      ExportRuleOp.gt => xs('exs_op_gt', '> greater than', '> أكبر من'),
      ExportRuleOp.ge => xs('exs_op_ge', '≥ at least', '≥ أكبر من أو يساوي'),
      ExportRuleOp.lt => xs('exs_op_lt', '< less than', '< أصغر من'),
      ExportRuleOp.le => xs('exs_op_le', '≤ at most', '≤ أصغر من أو يساوي'),
      ExportRuleOp.contains => xs('exs_op_contains', 'contains', 'يحتوي على'),
      ExportRuleOp.empty => xs('exs_op_empty', 'is empty', 'فارغ'),
      ExportRuleOp.notEmpty => xs('exs_op_not_empty', 'is not empty', 'غير فارغ'),
    };

/// A plain-language sentence of a rule ("Score < 50 → red text, bold").
String exportRuleSentence(ExportRule r, String Function(String id) labelOf) {
  final st = r.style;
  final parts = [
    if (st.hide) xs('exs_rule_hide_short', 'hide the row', 'إخفاء الصف'),
    if (st.color != null) xs('exs_rule_color_short', 'text colour', 'لون النص'),
    if (st.background != null) xs('exs_rule_bg_short', 'background', 'خلفية'),
    if (st.bold) xs('exs_rule_bold_short', 'bold', 'عريض'),
    if ((st.label ?? '').isNotEmpty) '“${st.label}”',
  ];
  final cond = '${labelOf(r.field)} ${exportRuleOpLabel(r.op)}${r.op.needsValue ? ' ${r.value ?? ''}' : ''}';
  return parts.isEmpty ? cond : '$cond → ${parts.join(', ')}';
}

/// The rule list editor. Mutates [rules] and calls [onChanged]. [columns] are the fields a rule may test.
class ExportRuleBuilder extends StatefulWidget {
  const ExportRuleBuilder({super.key, required this.columns, required this.labelOf, required this.rules, required this.onChanged});
  final List<AppExportColumn> columns;
  final String Function(AppExportColumn c) labelOf;
  final List<ExportRule> rules;
  final VoidCallback onChanged;

  @override
  State<ExportRuleBuilder> createState() => _ExportRuleBuilderState();
}

class _ExportRuleBuilderState extends State<ExportRuleBuilder> {
  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(xs('exs_rules_hint', 'Style the cells that match a condition — in Excel, Word and PDF alike.', 'نسّق الخلايا التي تطابق شرطًا — في Excel وWord وPDF معًا.'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      if (widget.rules.isEmpty)
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll),
          child: Row(children: [
            Icon(Icons.format_color_fill_rounded, color: c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(xs('exs_rules_empty', 'No rules yet. Example: Status = Late → red text.', 'لا قواعد بعد. مثال: الحالة = متأخر ← نص أحمر.'), style: appText(13, w: FontWeight.w400, c: c.textMedium))),
          ]),
        ),
      for (var i = 0; i < widget.rules.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.sm),
        _RuleCard(
          key: ObjectKey(widget.rules[i]),
          index: i,
          rule: widget.rules[i],
          columns: widget.columns,
          labelOf: widget.labelOf,
          onChanged: () => _changed(() {}),
          onDelete: () => _changed(() => widget.rules.removeAt(i)),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: widget.columns.isEmpty || widget.rules.length >= 100
              ? null
              : () => _changed(() => widget.rules.add(ExportRule(field: widget.columns.first.id, style: ExportRuleStyle(color: 'B91C1C')))),
          icon: const Icon(Icons.add_rounded),
          label: Text(xs('exs_rule_add', 'Add a rule', 'إضافة قاعدة')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
        ),
      ),
    ]);
  }
}

class _RuleCard extends StatefulWidget {
  const _RuleCard({super.key, required this.index, required this.rule, required this.columns, required this.labelOf, required this.onChanged, required this.onDelete});
  final int index;
  final ExportRule rule;
  final List<AppExportColumn> columns;
  final String Function(AppExportColumn c) labelOf;
  final VoidCallback onChanged, onDelete;

  @override
  State<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends State<_RuleCard> {
  late final _value = TextEditingController(text: widget.rule.value == null ? '' : '${widget.rule.value}');
  late final _label = TextEditingController(text: widget.rule.style.label ?? '');

  ExportRule get r => widget.rule;

  @override
  void dispose() {
    _value.dispose();
    _label.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  Future<void> _pickColor(bool background) async {
    final cur = background ? r.style.background : r.style.color;
    Color? picked = cur == null ? null : exportColor(cur);
    final ok = await showAppSheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(background ? xs('exs_rule_bg', 'Cell background', 'خلفية الخلية') : xs('exs_rule_color', 'Text colour', 'لون النص')),
            StudioColorField(
              value: picked,
              allowNone: true,
              swatches: background
                  ? const [Color(0xFFFDE7E7), Color(0xFFFFF4DB), Color(0xFFE3F5EC), Color(0xFFE6EEFB), Color(0xFFF3E8FF), Color(0xFFEEF1F4), Color(0xFFFEF9C3), Color(0xFFCCFBF1)]
                  : kStudioSwatches,
              onChanged: (v) => set(() => picked = v),
            ),
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(label: xs('exs_apply', 'Apply', 'تطبيق'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    _set(() {
      final hex = picked == null ? null : studioHex(picked!);
      if (background) {
        r.style.background = hex;
      } else {
        r.style.color = hex;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = widget.columns.where((x) => x.id == r.field).firstOrNull;
    final numeric = col?.numeric ?? false;
    final fieldDrop = AppDropdown<String>(
      value: col?.id,
      decoration: InputDecoration(isDense: true, labelText: xs('exs_rule_field', 'Field', 'الحقل')),
      items: [for (final x in widget.columns) DropdownMenuItem(value: x.id, child: Text(widget.labelOf(x), maxLines: 1, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => _set(() => r.field = v ?? r.field),
    );
    final opDrop = AppDropdown<ExportRuleOp>(
      value: r.op,
      decoration: InputDecoration(isDense: true, labelText: xs('exs_rule_condition', 'Condition', 'الشرط')),
      items: [for (final op in ExportRuleOp.values) DropdownMenuItem(value: op, child: Text(exportRuleOpLabel(op), maxLines: 1, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => _set(() => r.op = v ?? r.op),
    );
    Widget swatchButton(String label, String? hex, bool background) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: () => _pickColor(background),
            borderRadius: AppRadius.chipAll,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              decoration: BoxDecoration(border: Border.all(color: c.divider), borderRadius: AppRadius.chipAll),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: hex == null ? c.cardBg : exportColor(hex), shape: BoxShape.circle, border: Border.all(color: c.divider)),
                  child: hex == null ? Icon(Icons.block_rounded, size: 12, color: c.textLight) : null,
                ),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textDark))),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('${xs('exs_rule', 'Rule', 'قاعدة')} ${widget.index + 1}', style: appText(13, w: FontWeight.w600, c: c.textMedium)),
          const Spacer(),
          IconButton(tooltip: xs('exs_rule_delete', 'Delete the rule', 'حذف القاعدة'), onPressed: widget.onDelete, icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
        ]),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 420) return Column(children: [fieldDrop, const SizedBox(height: AppSpace.xs), opDrop]);
          return Row(children: [Expanded(child: fieldDrop), const SizedBox(width: AppSpace.xs), Expanded(child: opDrop)]);
        }),
        if (r.op.needsValue && (col?.statusLabels?.isNotEmpty ?? false) && (r.op == ExportRuleOp.eq || r.op == ExportRuleOp.ne)) ...[
          const SizedBox(height: AppSpace.xs),
          AppDropdown<String>(
            value: col!.statusLabels!.containsKey('${r.value ?? ''}') ? '${r.value}' : null,
            decoration: InputDecoration(isDense: true, labelText: xs('exs_rule_value', 'Value', 'القيمة')),
            items: [for (final s in col.statusLabels!.entries) DropdownMenuItem(value: s.key, child: Text(s.value, maxLines: 1, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => _set(() => r.value = v),
          ),
        ] else if (r.op.needsValue) ...[
          const SizedBox(height: AppSpace.xs),
          TextField(
            controller: _value,
            keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            decoration: InputDecoration(isDense: true, labelText: xs('exs_rule_value', 'Value', 'القيمة')),
            onChanged: (v) => _set(() {
              final n = numeric ? num.tryParse(v.trim().replaceAll(',', '')) : null;
              r.value = n ?? v;
            }),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(xs('exs_rule_then', 'Then', 'عندها'), style: appText(12, w: FontWeight.w500, c: c.textMedium)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          swatchButton(xs('exs_rule_color', 'Text colour', 'لون النص'), r.style.color, false),
          swatchButton(xs('exs_rule_bg', 'Cell background', 'خلفية الخلية'), r.style.background, true),
          FilterChip(
            showCheckmark: false,
            label: Text(xs('exs_rule_bold', 'Bold', 'عريض')),
            avatar: const Icon(Icons.format_bold_rounded, size: 18),
            selected: r.style.bold,
            onSelected: (v) => _set(() => r.style.bold = v),
          ),
          FilterChip(
            showCheckmark: false,
            label: Text(xs('exs_rule_hide', 'Hide the row', 'إخفاء الصف')),
            avatar: const Icon(Icons.visibility_off_outlined, size: 18),
            selected: r.style.hide,
            onSelected: (v) => _set(() => r.style.hide = v),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: _label,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          decoration: InputDecoration(isDense: true, labelText: xs('exs_rule_label', 'Show this text instead (optional)', 'اعرض هذا النص بدلًا منها (اختياري)')),
          onChanged: (v) => _set(() => r.style.label = v.trim().isEmpty ? null : v.trim()),
        ),
      ]),
    );
  }
}

/// The rule builder in a sheet over a copy of [rules]; the edited list, or null when dismissed.
Future<List<ExportRule>?> showExportRulesSheet(BuildContext context, {required List<AppExportColumn> columns, required String Function(AppExportColumn c) labelOf, required List<ExportRule> rules}) {
  final draft = [for (final r in rules) r.copy()];
  return showAppSheet<List<ExportRule>>(
    context,
    (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(xs('exs_rules_title', 'Highlight rules', 'قواعد التمييز')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: ExportRuleBuilder(columns: columns, labelOf: labelOf, rules: draft, onChanged: () {}),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
        child: AppPrimaryButton(label: xs('exs_apply_rules', 'Apply the rules', 'تطبيق القواعد'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, draft)),
      ),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Excel sheet preview
// ═════════════════════════════════════════════════════════════════════════════

/// The sheet as Excel will open it (first [maxRows] rows): column letters, the title band, the header, rows with
/// striping / borders / number formats / rules, the totals row. [export] is the language variant.
class ExportSheetPreview extends StatelessWidget {
  const ExportSheetPreview({super.key, required this.export, required this.columns, required this.sheet, this.rules = const [], this.numerals = ExportNumerals.western, this.maxRows = 8});
  final AppTableExport export;
  final List<String> columns;
  final XlsxSheetOptions sheet;
  final List<ExportRule> rules;
  final ExportNumerals numerals;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = export;
    final cols = e.resolve(columns);
    final rows = exportVisibleRows(rules, e.rows);
    final shown = rows.take(maxRows).toList();
    final brand = brandOf(e);
    final head = sheet.headerColor.isEmpty ? shadeHex(brand, .18) : sheet.headerColor;
    final headInk = sheet.headerFontColor.isEmpty ? onColorHex(head) : sheet.headerFontColor;
    final widths = columnWidths(cols, rows);
    double wOf(int k) => ((sheet.widths[cols[k].id] ?? widths[k]) * 6.2).clamp(44, 300).toDouble();
    final rtl = sheet.rtlFor(e.rtl ? 'ar' : 'en');
    final fs = (sheet.fontSize + 1).clamp(9, 16).toDouble();
    // the sheet's catalog font (Excel names it), else the document font
    final family = sheet.font.isEmpty ? _sheetFont : exportFlutterFont(sheet.font);
    final line = exportColor(sheet.borderColor);
    String digits(String s) => exportDigits(s, numerals);
    Widget cell(String text, double w, {Color? bg, Color? ink, bool bold = false, TextAlign align = TextAlign.start, bool letter = false}) => Container(
          width: w,
          height: letter ? 22 : 26,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            border: letter || sheet.borders ? Border(right: BorderSide(color: letter ? const Color(0xFFD9D9D9) : line, width: .6), bottom: BorderSide(color: letter ? const Color(0xFFD9D9D9) : line, width: .6)) : null,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: align,
                style: TextStyle(fontFamily: family, fontSize: letter ? 10.5 : fs, height: 1.1, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: ink ?? const Color(0xFF1F2933))),
          ),
        );
    TextAlign alignOf(AppExportColumn col) => switch (col.resolvedAlign) { AppColAlign.end => TextAlign.end, AppColAlign.center => TextAlign.center, _ => TextAlign.start };
    final totalW = 30 + [for (var k = 0; k < cols.length; k++) wOf(k)].fold<double>(0, (a, b) => a + b);
    final letterBg = const Color(0xFFF3F4F6);
    final rowsW = <Widget>[];
    var n = 1;
    Widget numberCell(String s) => cell(s, 30, bg: letterBg, ink: const Color(0xFF6B7280), letter: true, align: TextAlign.center);
    if (sheet.titleRow) {
      final title = sheet.title.trim().isEmpty ? e.title : sheet.title;
      rowsW.add(Row(children: [
        numberCell('${n++}'),
        Container(
          width: totalW - 30,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: exportColor(brand),
          alignment: AlignmentDirectional.centerStart,
          child: Row(children: [
            if (sheet.logoUrl.isNotEmpty) ...[Icon(Icons.image_outlined, size: 18, color: exportColor(onColorHex(brand))), const SizedBox(width: 6)],
            Expanded(child: Text(digits(title.replaceAll('{{title}}', e.title).replaceAll(RegExp(r'\{\{[a-z_]+\}\}'), '…')), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w700, color: exportColor(onColorHex(brand))))),
          ]),
        ),
      ]));
      rowsW.add(Row(children: [numberCell('${n++}'), SizedBox(width: totalW - 30, height: 10)]));
    }
    rowsW.add(Row(children: [
      numberCell('${n++}'),
      for (var k = 0; k < cols.length; k++) cell(digits(cols[k].label), wOf(k), bg: exportColor(head), ink: exportColor(headInk), bold: sheet.headerBold, align: TextAlign.center),
    ]));
    if (sheet.freezeHeader) rowsW.add(Container(height: 2, width: totalW, color: const Color(0xFF9CA3AF)));
    for (var i = 0; i < shown.length; i++) {
      final r = shown[i];
      final look = exportRowLook(rules, r);
      rowsW.add(Row(children: [
        numberCell('${n++}'),
        for (var k = 0; k < cols.length; k++)
          () {
            final col = cols[k];
            final st = look.of(col.id);
            final zebra = sheet.striping && i.isOdd ? exportColor(sheet.stripeColor) : null;
            return cell(
              digits(look.textOf(col.id, cellText(col, r[col.id]))),
              wOf(k),
              bg: st?.background != null ? exportColor(st!.background!) : zebra,
              ink: st?.color != null ? exportColor(st!.color!) : null,
              bold: st?.bold ?? false,
              align: alignOf(col),
            );
          }(),
      ]));
    }
    if (rows.length > shown.length) {
      rowsW.add(Padding(
        padding: const EdgeInsetsDirectional.only(start: 38, top: 4),
        child: Text('+ ${rows.length - shown.length} ${xs('exs_more_rows', 'more rows', 'صفًا أخرى')}', style: appText(12, w: FontWeight.w400, c: c.textMedium)),
      ));
    }
    if (shown.isEmpty) {
      rowsW.add(Padding(padding: const EdgeInsets.all(AppSpace.md), child: Text(xs('exs_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), style: AppType.meta(context))));
    }
    return Semantics(
      label: xs('exs_sheet_preview', 'Sheet preview', 'معاينة الورقة'),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
        clipBehavior: Clip.antiAlias,
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: AppHScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                cell('', 30, bg: letterBg, letter: true),
                for (var k = 0; k < cols.length; k++) cell(_letter(k), wOf(k), bg: letterBg, ink: const Color(0xFF6B7280), letter: true, align: TextAlign.center),
              ]),
              ...rowsW,
            ]),
          ),
        ),
      ),
    );
  }

  static String _letter(int c) {
    var n = c + 1, s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Summary line
// ═════════════════════════════════════════════════════════════════════════════

class ExportSummaryLine extends StatelessWidget {
  const ExportSummaryLine({super.key, required this.icon, required this.label, required this.value, this.onEdit});
  final IconData icon;
  final String label, value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onEdit,
      borderRadius: AppRadius.chipAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Icon(icon, size: 20, color: c.textMedium),
          const SizedBox(width: AppSpace.sm),
          SizedBox(width: 92, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w400, c: c.textMedium))),
          Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark))),
          if (onEdit != null) Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
      ),
    );
  }
}
