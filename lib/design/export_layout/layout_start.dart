// lib/design/export_layout/layout_start.dart
//
// The first screen of the export page — the quick path: Format · Language · a gallery of designs (the server's
// starters, else the local presets, then the person's and the organization's saved templates), each drawn as a small
// schematic from its own document (no server call per card). "Export now" runs with the chosen design at once;
// "Customize design" opens the designer (layout → design → preview). Also here: the thumbnail painter, the Excel
// note and the run panel (progress, cancel, keep working) the start and the preview steps share.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../features/admin/admin_common.dart' show t;
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../export/export_studio_model.dart' show exportLtr;
import '../export_hub/export_flow_parts.dart' show ExportFormatCard;
import '../studio/studio.dart' show kStudioPaper;
import 'layout_flow_controller.dart';
import 'layout_steps.dart' show LayoutCardGrid, LayoutChoiceCard, LayoutSection;

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Thumbnails
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// A small drawing of a design: the page, its header and the items as the layout lays them out (table rows, list
/// lines in 1 – 4 columns, cards in a grid, one big card for a page per item). Paper colours: it shows a document.
class LayoutDesignThumb extends StatelessWidget {
  const LayoutDesignThumb({super.key, required this.spec, this.height = 84});
  final LayoutThumbSpec spec;
  final double height;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          height: height,
          child: AspectRatio(
            aspectRatio: spec.landscape ? 1.35 : .74,
            child: CustomPaint(painter: _ThumbPainter(spec)),
          ),
        ),
      );
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.spec);
  final LayoutThumbSpec spec;

  static const _ink = Color(0xFF98A2B3), _soft = Color(0xFFE4E7EC), _head = Color(0xFFD0D5DD);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _head;
    final page = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    canvas.drawRRect(page, fill..color = kStudioPaper);
    canvas.drawRRect(page, line..color = _soft);
    final pad = size.shortestSide * .09;
    final inner = Rect.fromLTWH(pad, pad, size.width - 2 * pad, size.height - 2 * pad);
    void bar(Rect r, Color c) => canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.5)), fill..color = c);
    // the header band
    final headH = inner.height * .07;
    bar(Rect.fromLTWH(inner.left, inner.top, inner.width * .55, headH), _ink);
    final body = Rect.fromLTRB(inner.left, inner.top + headH + inner.height * .06, inner.right, inner.bottom);
    final lh = (body.height / 11).clamp(2.0, 6.0);
    switch (spec.mode) {
      case 'table':
        final cols = spec.tableColumns.clamp(2, 7);
        bar(Rect.fromLTWH(body.left, body.top, body.width, lh * 1.4), _head);
        for (var r = 0; r < 7; r++) {
          final y = body.top + lh * 1.4 + lh * 1.5 * (r + 1) - lh * .5;
          if (y + lh > body.bottom) break;
          if (r.isOdd) bar(Rect.fromLTWH(body.left, y - lh * .2, body.width, lh * 1.3), _soft);
          for (var c = 0; c < cols; c++) {
            final cw = body.width / cols;
            bar(Rect.fromLTWH(body.left + c * cw + 1.5, y + lh * .25, cw * .62, lh * .5), _ink);
          }
        }
      case 'list':
        final n = spec.columns.clamp(1, 4);
        final gap = 3.0;
        final cw = (body.width - gap * (n - 1)) / n;
        for (var c = 0; c < n; c++) {
          final x = body.left + c * (cw + gap);
          for (var r = 0; r < 9; r++) {
            final y = body.top + r * lh * 1.5;
            if (y + lh > body.bottom) break;
            bar(Rect.fromLTWH(x, y, cw * (r.isEven ? .95 : .72), lh * .55), _ink);
          }
        }
      case 'page':
        final r = RRect.fromRectAndRadius(Rect.fromLTRB(body.left, body.top, body.right, body.bottom), const Radius.circular(2));
        canvas.drawRRect(r, line);
        bar(Rect.fromCenter(center: Offset(body.center.dx, body.top + body.height * .3), width: body.width * .6, height: lh * .8), _ink);
        bar(Rect.fromCenter(center: Offset(body.center.dx, body.top + body.height * .45), width: body.width * .4, height: lh * .5), _head);
        bar(Rect.fromCenter(center: Offset(body.center.dx, body.top + body.height * .58), width: body.width * .5, height: lh * .5), _head);
      default:
        final n = spec.perLine.clamp(1, 4);
        final rows = spec.fill && spec.perPage > 0 ? (spec.perPage / n).ceil().clamp(1, 5) : (n == 1 ? 4 : 3);
        const gap = 3.0;
        final cw = (body.width - gap * (n - 1)) / n;
        final ch = spec.fill ? (body.height - gap * (rows - 1)) / rows : (n == 1 ? lh * 2.6 : lh * 3.4);
        for (var r = 0; r < rows; r++) {
          final y = body.top + r * (ch + gap);
          if (y + ch > body.bottom + .5) break;
          for (var c = 0; c < n; c++) {
            final x = body.left + c * (cw + gap);
            final cell = Rect.fromLTWH(x, y, cw, ch);
            canvas.drawRRect(RRect.fromRectAndRadius(cell, const Radius.circular(2)), line);
            bar(Rect.fromLTWH(x + 2.5, y + ch * .22, cw * .6, (ch * .14).clamp(1.5, 4.0)), _ink);
            bar(Rect.fromLTWH(x + 2.5, y + ch * .5, cw * .4, (ch * .1).clamp(1.2, 3.0)), _head);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.spec != spec;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Excel note
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// What Excel keeps of a design (shown whenever the format is Excel).
class LayoutExcelNote extends StatelessWidget {
  const LayoutExcelNote({super.key});

  @override
  Widget build(BuildContext context) => AppBanner(
        icon: Icons.table_chart_outlined,
        text: t(
          'إكسل يحتفظ بالبيانات والتنسيق (الجداول، العناوين، عرض الأعمدة، صيغ الأرقام والتواريخ)؛ العناصر الحرة تُبسَّط.',
          'Excel keeps the data and its formatting (tables, headers, column widths, number and date formats); free-form elements are simplified.',
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The start screen
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class LayoutStartStep extends StatelessWidget {
  const LayoutStartStep({super.key, required this.flow, this.formats = AppExportFormat.values});
  final LayoutFlowController flow;
  final List<AppExportFormat> formats;

  Future<void> _pick(LayoutGalleryItem g) async {
    final err = await flow.pickGallery(g);
    if (err != null) showAppNotice(err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final langs = flow.doc.languages;
    final key = langs.length > 1 ? 'both' : langs.first;
    final c = context.colors;
    final lang = flow.lang;
    Widget langCard(String id, String title, String hint, IconData icon) => LayoutChoiceCard(
          key: ValueKey('layout-lang-$id'),
          title: title,
          hint: hint,
          icon: icon,
          selected: key == id,
          onTap: () => flow.setLanguages(id == 'both' ? const ['ar', 'en'] : [id]),
        );
    final gallery = flow.gallery;
    final selected = flow.selectedGalleryId;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      // the export in progress is the first thing on the screen: it must never hide below the gallery
      if (flow.phase != LayoutRunPhase.idle) LayoutRunPanel(key: const ValueKey('layout-start-run'), flow: flow),
      LayoutSection(title: t('صيغة الملف', 'File format'), children: [
        LayoutCardGrid(min: 150, children: [
          for (final f in formats)
            ExportFormatCard(key: ValueKey('layout-format-${f.ext}'), format: f, selected: flow.doc.format == f.ext, onTap: () => flow.setFormat(f.ext)),
        ]),
        if (flow.isXlsx) ...[const SizedBox(height: AppSpace.sm), const LayoutExcelNote(key: ValueKey('layout-excel-note'))],
      ]),
      LayoutSection(
        title: t('اللغة', 'Language'),
        subtitle: t('لكل لغة تصميمها الخاص: العربي من اليمين والإنجليزي من اليسار.', 'Each language has its own design: Arabic reads from the right, English from the left.'),
        children: [
          LayoutCardGrid(min: 170, children: [
            langCard('ar', t('العربية', 'Arabic'), t('ملف عربي', 'An Arabic file'), Icons.translate_rounded),
            langCard('en', t('الإنجليزية', 'English'), t('ملف إنجليزي', 'An English file'), Icons.language_rounded),
            langCard('both', t('كلتاهما', 'Both'), flow.isXlsx ? t('ورقتان في ملف واحد', 'Two sheets in one file') : t('ملفان في ملف مضغوط', 'Two files in a zip'), Icons.g_translate_rounded),
          ]),
        ],
      ),
      LayoutSection(
        key: const ValueKey('layout-gallery'),
        title: t('اختر تصميمًا', 'Pick a design'),
        subtitle: t('ثم صدّر فورًا، أو خصّص التصميم أولًا.', 'Then export right away, or customize it first.'),
        children: [
          if ((flow.templatesLoading || flow.startersLoading) && gallery.isEmpty)
            const AppSkeletonBox(width: double.infinity, height: 120)
          else
            LayoutCardGrid(min: 150, children: [
              for (final g in gallery)
                LayoutChoiceCard(
                  key: ValueKey('layout-${g.kind == 'template' ? 'tpl' : g.kind}-${g.id.substring(g.id.indexOf(':') + 1)}'),
                  title: g.name(lang),
                  hint: [if (g.badge(lang) != null) g.badge(lang)!, if (g.hint(lang).isNotEmpty) g.hint(lang)].join(' · '),
                  selected: selected == g.id,
                  picture: g.thumb == null ? _NoThumb(kind: g.kind) : LayoutDesignThumb(spec: g.thumb!),
                  onTap: () => _pick(g),
                ),
            ]),
          if (flow.templatesError != null) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(icon: Icons.cloud_off_rounded, text: flow.templatesError!, color: c.danger, action: TextButton(onPressed: flow.loadTemplates, child: Text(t('إعادة المحاولة', 'Retry')))),
          ] else if (flow.templatesMissing) ...[
            const SizedBox(height: AppSpace.sm),
            Text(t('القوالب المحفوظة تحتاج تحديث الخادم.', 'Saved templates need a server update.'), style: appText(12.5, c: c.textMedium)),
          ],
        ],
      ),
    ]);
  }
}

class _NoThumb extends StatelessWidget {
  const _NoThumb({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: kStudioPaper, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Icon(kind == 'last' ? Icons.history_rounded : Icons.bookmark_outline_rounded, size: 30, color: c.textMedium),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The run panel: progress, cancel, keep working
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

String layoutCount(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// The export in progress (or finished): what is happening, rows done / in all and the percentage, cancel, and a
/// reminder that leaving the page lets the export finish in the background.
class LayoutRunPanel extends StatelessWidget {
  const LayoutRunPanel({super.key, required this.flow});
  final LayoutFlowController flow;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    final c = context.colors;
    final run = f.run;
    final phase = f.phase;
    final total = f.rowsTotal;
    final pct = run?.progress ?? 0;
    final rowsText = total == null ? '' : '${layoutCount(f.rowsDone)} / ${layoutCount(total)} ${t('صف', 'rows')} · ';
    final status = switch (phase) {
      LayoutRunPhase.preparing => f.uploading ? '${t('يرسل', 'Sending')} ${layoutCount(f.uploadCount)} ${t('صف إلى الخادم…', 'rows to the server…')}' : t('يجهّز التصدير…', 'Preparing the export…'),
      LayoutRunPhase.running => '${t('يُنشئ الملف', 'Creating the file')} · $rowsText$pct%',
      LayoutRunPhase.downloading => t('يُنزّل الملف…', 'Downloading the file…'),
      LayoutRunPhase.done => '${t('تم الحفظ', 'Saved')}: ${exportLtr(f.savedName ?? '')}',
      LayoutRunPhase.failed => f.runError ?? '',
      LayoutRunPhase.cancelled => t('أُلغي التصدير', 'The export was cancelled'),
      LayoutRunPhase.idle => '${exportLtr(f.fileName)} · ${layoutCount(f.export.rows.length)} ${t('صف', 'rows')}',
    };
    return LayoutSection(title: t('التصدير', 'Export'), children: [
      Text(status, key: const ValueKey('layout-run-status'), style: appText(13, w: FontWeight.w500, c: phase == LayoutRunPhase.failed ? c.danger : c.textDark)),
      if (f.busy) ...[
        const SizedBox(height: AppSpace.sm),
        ClipRRect(
          borderRadius: AppRadius.chipAll,
          child: LinearProgressIndicator(value: phase == LayoutRunPhase.running ? pct / 100 : null, minHeight: 6, backgroundColor: c.divider, color: c.primary),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          t('يمكنك مغادرة الصفحة: يستمر التصدير ويُحفظ الملف عند اكتماله.', 'You can leave this page: the export keeps going and the file is saved when it is ready.'),
          key: const ValueKey('layout-run-hint'),
          style: appText(12, c: c.textMedium),
        ),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          key: const ValueKey('layout-run-cancel'),
          onPressed: f.cancelRun,
          icon: const Icon(Icons.close_rounded),
          label: Text(t('إلغاء التصدير', 'Cancel the export')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        ),
      ] else if (phase == LayoutRunPhase.done) ...[
        const SizedBox(height: AppSpace.xs),
        TextButton.icon(onPressed: f.downloadAgain, icon: const Icon(Icons.download_rounded), label: Text(t('تنزيل الملف مجددًا', 'Download the file again'))),
      ],
    ]);
  }
}
