// lib/design/export_hub/export_designer.dart
//
// The Export Studio's page designer, on the shared studio engine (lib/design/studio/, D-133): the sheet with its
// margins, header / footer, frame and watermark, every block at its place (drag, resize with 8 handles, snap guides,
// align / distribute, nudge with the arrows, duplicate, delete, z order, undo / redo, zoom — the engine's
// StudioToolbar and keyboard), and a property panel built from studio_props.dart: the selected element (text,
// placeholders, image, signature name + title, font, size, weight, colour, alignment, background, position and size
// in millimetres), the page (paper, orientation, margins, direction, base font, header / footer with
// {{org_name}} {{date}} {{page}} {{pages}} {{rows}} {{exporter}}, page numbers, frame, watermark), the table and the
// vote results. Phones get a calm notice first (StudioSmallScreenGate), then the canvas with the panel in a sheet.
//
//     ExportDesignerPage(design: d, dataset: ds, module: 'table', lang: 'ar', onSave: (design, name) async {…})
//
// The document stays ExportDesign (export_design.dart): the adapter maps its blocks (fractions of the content box,
// x from the PHYSICAL left like the writers) to engine items in millimetres; snapshot = design.toJson().
// `ExportPagePreview` and `VoteResultPreview` take plain values (the flow's live preview, the layout harness).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:http/http.dart' as http;

import '../../features/admin/admin_common.dart' show SheetHeader, t, toast;
import '../../features/org/org_providers.dart' show orgBase;
import '../../features/org/org_ui.dart' show orgFileUrl;
import '../../features/shared/rag/app_assistant.dart' show AppAssistant;
import '../../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../app_kit.dart';
import '../app_tokens.dart';
import '../export/export_studio_model.dart';
import '../studio/studio.dart';
import '../export/export_fonts.dart' show ExportFonts;
import 'export_design.dart';
import 'export_layout.dart';
import 'export_watermark_editor.dart';
import 'export_pdf.dart';

// The page preview is the printed sheet: paper and ink are document colours, not theme colours.
const _paper = Color(0xFFFFFFFF);

Color exportColor(String hex, [Color fallback = const Color(0xFF1E293B)]) {
  final h = hexOf(hex, '');
  return h.isEmpty ? fallback : Color(int.parse('FF$h', radix: 16));
}

/// The Flutter font family of a design family: the catalog font registered for the previews (`xf_<id>`, the PDF's
/// own copy of the files — see ExportFonts.ensurePreview). Asking for it starts loading it (once); until it lands the
/// text draws in the fallback and redraws when the font arrives.
String exportFlutterFont(String family) {
  final f = ExportFonts.byId(family.isEmpty ? ExportFonts.defaultId : family);
  ExportFonts.ensurePreview(f.id);
  return f.previewFamily;
}

/// The fallback families of a design family in the previews (its Arabic stand-in, then IBM Plex Sans Arabic) — what
/// the PDF falls back to.
List<String> exportFlutterFallback(String family) => ExportFonts.byId(family.isEmpty ? ExportFonts.defaultId : family).previewFallback;

/// Swatches offered for text, lines and the table header.
const exportSwatches = ['1E293B', '64748B', '0F766E', '1E40AF', '7C3AED', '991B1B', '92400E', '166534', '000000', 'FFFFFF'];

List<Color> get _studioSwatches => [for (final h in exportSwatches) exportColor(h)];

String? _hexOfColor(Color? c) => c == null ? null : studioHex(c);

// ═════════════════════════════════════════════════════════════════════════════
//  Images
// ═════════════════════════════════════════════════════════════════════════════

final _imageCache = <String, Uint8List>{};

/// Downloads the logo / signature images a design refers to (org file paths are made absolute). Failures are
/// skipped: the block then prints nothing.
Future<Map<String, Uint8List>> loadExportImages(ExportDesign d) async {
  final out = <String, Uint8List>{};
  for (final b in d.blocks) {
    if (!b.isImage || b.url.isEmpty) continue;
    final bytes = await loadExportImage(b.url);
    if (bytes != null) out[b.url] = bytes;
  }
  final wm = d.watermark;
  if (wm.visible && wm.isImage) {
    final bytes = await loadExportImage(wm.imageUrl);
    if (bytes != null) out[wm.imageUrl] = bytes;
  }
  return out;
}

/// One image by URL (cached); null when it cannot be read.
Future<Uint8List?> loadExportImage(String url) async {
  if (url.isEmpty) return null;
  final cached = _imageCache[url];
  if (cached != null) return cached;
  try {
    final res = await http.get(Uri.parse(orgFileUrl(url))).timeout(const Duration(seconds: 25));
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return _imageCache[url] = res.bodyBytes;
  } catch (_) {}
  return null;
}

/// Remembers bytes for a URL (after an upload, so the preview does not download what it just sent).
void rememberExportImage(String url, Uint8List bytes) => _imageCache[url] = bytes;

Uint8List? cachedExportImage(String url) => _imageCache[url];

// ═════════════════════════════════════════════════════════════════════════════
//  Vote result preview (presentational)
// ═════════════════════════════════════════════════════════════════════════════

/// The vote result of one item as the PDF prints it: [beside] = the compact side version, else the full line.
class VoteResultPreview extends StatelessWidget {
  const VoteResultPreview({super.key, required this.votes, required this.result, required this.lang, required this.fontSize, this.beside = false, this.family = 'tajawal'});
  final ExportVotes votes;
  final ExportVoteResult result;
  final String lang, family;
  final double fontSize;
  final bool beside;

  @override
  Widget build(BuildContext context) {
    final lb = ExportLabels(lang);
    final (fillHex, inkHex) = voteOutcomeColors(result.outcome);
    final small = fontSize * (beside ? .8 : .85);
    TextStyle st({bool bold = false, String? color, double? size}) =>
        TextStyle(fontFamily: exportFlutterFont(family), fontSize: size ?? small, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: exportColor(color ?? exportMuted), height: 1.2);
    Widget pill() => Container(
          padding: EdgeInsets.symmetric(horizontal: small * .8, vertical: small * .2),
          decoration: BoxDecoration(color: exportColor(fillHex), borderRadius: BorderRadius.circular(small)),
          child: Text(lb.outcome(result.outcome), maxLines: 1, overflow: TextOverflow.ellipsis, style: st(bold: true, color: inkHex)),
        );
    Widget bar({double height = 6}) {
      final total = result.eligible > 0 ? result.eligible : (result.cast == 0 ? 1 : result.cast);
      final rest = (total - result.cast).clamp(0, total);
      return ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Row(children: [
            if (result.approve > 0) Expanded(flex: result.approve, child: ColoredBox(color: exportColor(voteApproveHex))),
            if (result.reject > 0) Expanded(flex: result.reject, child: ColoredBox(color: exportColor(voteRejectHex))),
            if (result.abstain > 0) Expanded(flex: result.abstain, child: ColoredBox(color: exportColor(voteAbstainHex))),
            if (rest > 0) Expanded(flex: rest, child: ColoredBox(color: exportColor(voteRestHex))),
          ]),
        ),
      );
    }

    if (beside) {
      return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        if (votes.showOutcome && votes.style != 'text') pill(),
        if (votes.showOutcome && votes.style == 'text') Text(lb.outcome(result.outcome), maxLines: 1, overflow: TextOverflow.ellipsis, style: st(bold: true, color: inkHex)),
        if (votes.style == 'bar') ...[const SizedBox(height: 3), SizedBox(width: small * 8, child: bar(height: 5))],
        if (votes.showPercent) ...[const SizedBox(height: 2), Text(result.percentText, style: st(bold: true, color: exportInk))],
        if (votes.showCounts) Text('${result.approve} / ${result.reject} / ${result.abstain}', style: st(size: small * .95)),
      ]);
    }
    final line = [
      if (votes.showOutcome && votes.style != 'pill') '${lb.result}: ${lb.outcome(result.outcome)}',
      if (votes.showCounts) lb.counts(result),
      if (votes.showPercent) '${lb.approve} ${result.percentText}',
    ].join('  ·  ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (votes.style == 'bar') ...[bar(), const SizedBox(height: 3)],
      Row(children: [
        if (votes.showOutcome && votes.style == 'pill') ...[pill(), const SizedBox(width: 6)],
        if (line.isNotEmpty) Expanded(child: Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: st())),
      ]),
      if (votes.showVoters && result.voters.isNotEmpty)
        Text('${lb.voters}: ${result.voters.map((x) => '${x['name']} (${lb.vote('${x['vote']}')})').join('، ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: st(size: small * .9)),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared drawing: paper decorations and block content
// ═════════════════════════════════════════════════════════════════════════════

/// The values a preview fills in: the dataset's placeholders plus the visible row count after the rules.
Map<String, String> _previewValues(ExportDesign d, ExportDataset ds, ExportContent? c) {
  final v = ds.placeholderValues(d.lang);
  if (c != null && c.rules.isNotEmpty) v['rows'] = '${exportVisibleRows(c.rules, ds.rows).length}';
  return v;
}

String _digits(String s, ExportContent? c) => c == null ? s : exportDigits(s, c.numerals);

/// The paper's own layer (behind the blocks): header and footer text in the margins, the frame, the watermark.
/// [scale] = screen pixels per millimetre; [box] = the paper size in pixels.
class _PaperDecor extends StatelessWidget {
  const _PaperDecor({required this.design, required this.values, required this.scale, this.content, this.images});
  final ExportDesign design;
  final Map<String, String> values;
  final double scale;
  final ExportContent? content;

  /// Image bytes by URL (an image watermark uploaded this session).
  final Map<String, Uint8List>? images;

  @override
  Widget build(BuildContext context) {
    final d = design;
    final ml = d.page.left * scale, mr = d.page.right * scale, mt = d.page.top * scale, mb = d.page.bottom * scale;
    // points → millimetres → pixels, at the writers' sizes (export_layout.dart)
    TextStyle st({bool footer = false}) => TextStyle(
        fontFamily: exportFlutterFont(d.fontFamily),
        fontSize: ((footer ? exportFooterSize(d) : exportHeaderSize(d)) * .3528 * scale).clamp(3, 40).toDouble(),
        color: exportColor(exportMuted));
    String fill(String s) => _digits(fillPlaceholders(s, values).replaceAll('{{page}}', '1').replaceAll('{{pages}}', '1'), content);
    Widget hf(String start, String end, {bool footer = false}) => Row(children: [
          Expanded(child: Text(start, maxLines: 1, overflow: TextOverflow.ellipsis, style: st(footer: footer))),
          if (end.isNotEmpty) Flexible(child: Text(end, maxLines: 1, overflow: TextOverflow.clip, style: st(footer: footer))),
        ]);
    final lb = ExportLabels(d.lang);
    return Stack(clipBehavior: Clip.hardEdge, children: [
      if (d.watermark.visible)
        Positioned(
          left: ml,
          top: mt,
          right: mr,
          bottom: mb,
          child: LayoutBuilder(
            builder: (_, box) => _Watermark(mark: d.watermark, family: exportFlutterFont(d.fontFamily), scale: scale, rtl: d.rtl, contentWidth: box.maxWidth, images: images),
          ),
        ),
      if (d.frame.visible)
        Positioned(
          left: math.max(0, ml - d.frame.inset * scale),
          top: math.max(0, mt - d.frame.inset * scale),
          right: math.max(0, mr - d.frame.inset * scale),
          bottom: math.max(0, mb - d.frame.inset * scale),
          child: StudioBorderBox(
            // points → millimetres → pixels
            border: StudioBorder(
              style: StudioBorderStyle.values.byName(d.frame.style == 'none' ? 'none' : d.frame.style),
              width: d.frame.width * .3528,
              color: exportColor(d.frame.color),
              radius: d.frame.radius * .3528,
            ),
            scale: scale,
          ),
        ),
      if (d.headerText.trim().isNotEmpty || d.showDate)
        Positioned(left: ml, right: mr, top: (mt * .4).clamp(1, math.max(1.0, mt)), child: hf(fill(d.headerText), d.showDate ? _digits(values['date'] ?? '', content) : '')),
      if (d.footerText.trim().isNotEmpty || d.showPageNumbers)
        Positioned(
          left: ml,
          right: mr,
          bottom: (mb * .35).clamp(1, math.max(1.0, mb)),
          child: hf(fill(d.footerText), d.showPageNumbers ? _digits(exportFooterPageText(lb.page, lb.of, 1, 1), content) : '', footer: true),
        ),
    ]);
  }
}

/// The watermark in the content box, at its position, turned and faded like the PDF / Word / Excel files
/// (export_watermark.dart). [contentWidth] in pixels sizes an image watermark.
class _Watermark extends StatelessWidget {
  const _Watermark({required this.mark, required this.family, required this.scale, required this.rtl, required this.contentWidth, this.images});
  final ExportWatermark mark;
  final String family;
  final double scale, contentWidth;
  final bool rtl;
  final Map<String, Uint8List>? images;

  @override
  Widget build(BuildContext context) {
    final (ax, ay) = exportWatermarkAlign(mark.position, rtl);
    final Widget body;
    if (mark.isImage) {
      final known = images?[mark.imageUrl];
      Widget pic(Uint8List? b) => b == null ? const SizedBox.shrink() : Image.memory(b, width: mark.imageWidth * contentWidth, fit: BoxFit.contain, gaplessPlayback: true);
      body = Opacity(
        opacity: mark.opacity.clamp(0, 1).toDouble(),
        child: known != null ? pic(known) : FutureBuilder<Uint8List?>(future: loadExportImage(mark.imageUrl), builder: (_, s) => pic(s.data)),
      );
    } else {
      body = Text(
        mark.text.trim(),
        maxLines: 1,
        softWrap: false,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        style: TextStyle(
          fontFamily: family,
          fontSize: (mark.size * .3528 * scale).clamp(4, 400),
          fontWeight: FontWeight.w800,
          color: exportColor(mark.color).withValues(alpha: mark.opacity.clamp(0, 1).toDouble()),
        ),
      );
    }
    return IgnorePointer(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        alignment: Alignment(ax, ay),
        child: Transform.rotate(angle: mark.angle * math.pi / 180, child: body),
      ),
    );
  }
}

/// One block's printed content at [scale] px / mm (no selection chrome: the engine / the preview draws that).
class _BlockContent extends StatelessWidget {
  const _BlockContent({required this.design, required this.dataset, required this.block, required this.values, required this.scale, this.images, this.content, this.placeholders = true});
  final ExportDesign design;
  final ExportDataset dataset;
  final ExportBlock block;
  final Map<String, String> values;
  final double scale;
  final Map<String, Uint8List>? images;
  final ExportContent? content;

  /// An empty logo / signature box shows where it sits (the studio); a print preview draws nothing there.
  final bool placeholders;

  @override
  Widget build(BuildContext context) {
    final d = design;
    final b = block;
    // 1 pt = 0.3528 mm on paper
    double pt(double size) => (size * .3528 * scale).clamp(2.0, 120.0);
    final family = exportFlutterFont(b.font.family.isEmpty ? d.fontFamily : b.font.family);
    final ta = switch (b.align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start };
    final dir = d.rtl ? TextDirection.rtl : TextDirection.ltr;
    final al = switch (b.align) {
      'center' => Alignment.topCenter,
      'end' => AlignmentDirectional.topEnd.resolve(dir),
      _ => AlignmentDirectional.topStart.resolve(dir),
    };
    final ink = b.font.color.isEmpty ? d.fontColor : b.font.color;
    TextStyle st({double? size, bool? bold, String? color}) => TextStyle(
        fontFamily: family, fontSize: pt(size ?? b.font.size), color: exportColor(color ?? ink), height: d.lineSpacing, fontWeight: (bold ?? b.font.bold) ? FontWeight.w800 : FontWeight.w500);
    String fill(String s) => _digits(fillPlaceholders(s, values), content);
    Widget body;
    switch (b.kind) {
      case 'table':
        body = _TablePreview(design: d, dataset: dataset, fs: pt(d.table.fontSize), family: exportFlutterFont(d.fontFamily), content: content);
      case 'items':
        body = _ItemsPreview(design: d, dataset: dataset, pt: pt, family: exportFlutterFont(d.fontFamily));
      case 'logo':
        body = _netImage(b.url, Icons.image_rounded, t('الشعار', 'Logo'), al);
      case 'signature':
        final name = fill(b.name).trim(), title = fill(b.title).trim();
        body = Column(children: [
          Expanded(child: _netImage(b.url, Icons.draw_rounded, t('التوقيع', 'Signature'), al)),
          if (name.isNotEmpty) Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: ta, style: st(bold: true)),
          if (title.isNotEmpty) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: ta, style: st(size: b.font.size * .85, bold: false, color: exportMuted)),
        ]);
      case 'line':
        body = LayoutBuilder(
            builder: (context, box) => Align(
                alignment: Alignment.topCenter,
                child: Container(height: box.maxHeight.clamp(.5, 6).toDouble(), color: exportColor(b.color.isEmpty ? exportLine : b.color))));
      default:
        body = Align(alignment: al, child: Text(fill(b.text), textAlign: ta, overflow: TextOverflow.fade, style: st()));
    }
    // flow blocks print as many rows as there are; the box shows what fits (never an overflow)
    if (b.isFlow) body = SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: body);
    final framed = Directionality(textDirection: dir, child: ClipRect(child: body));
    if (b.background.isEmpty || b.isFlow || b.kind == 'line') return framed;
    return DecoratedBox(
      decoration: BoxDecoration(color: exportColor(b.background), borderRadius: BorderRadius.circular(1.2 * scale)),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: 1.6 * scale, vertical: .8 * scale), child: framed),
    );
  }

  Widget _netImage(String url, IconData icon, String label, AlignmentGeometry al) {
    final cached = images?[url] ?? cachedExportImage(url);
    if (cached != null) return Align(alignment: al, child: Image.memory(cached, fit: BoxFit.contain));
    if (url.isNotEmpty) return Align(alignment: al, child: Image.network(orgFileUrl(url), fit: BoxFit.contain, errorBuilder: (_, _, _) => _placeholder(icon, label)));
    return _placeholder(icon, label);
  }

  Widget _empty() => const SizedBox.shrink();

  Widget _placeholder(IconData icon, String label) {
    if (!placeholders) return _empty();
    final ink = exportColor(exportInk);
    return DecoratedBox(
      decoration: BoxDecoration(color: ink.withValues(alpha: .04), borderRadius: BorderRadius.circular(4), border: Border.all(color: ink.withValues(alpha: .12))),
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: ink.withValues(alpha: .45)),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .6))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page preview (presentational)
// ═════════════════════════════════════════════════════════════════════════════

/// The designed page at any width, read-only: the paper, the margin guide, header / footer, frame, watermark and
/// every block at its fractions (the flow's live preview, thumbnails). Editing happens on the studio engine
/// ([ExportDesignerPage]: StudioCanvas + ExportStudioAdapter). [content] applies the flow's choices to the table
/// (columns, labels, rules, numerals).
class ExportPagePreview extends StatelessWidget {
  const ExportPagePreview({
    super.key,
    required this.design,
    required this.dataset,
    this.maxWidth = 620,
    this.images,
    this.content,
  });

  final ExportDesign design;
  final ExportDataset dataset;
  final double maxWidth;

  /// Image bytes by URL (uploaded this session); the rest load from the network.
  final Map<String, Uint8List>? images;
  final ExportContent? content;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = design;
    final (pwMm, phMm) = d.page.mm;
    final values = _previewValues(d, dataset, content);
    // a text that names its family but no fallback inherits the page font's (the PDF's) fallback chain
    return DefaultTextStyle.merge(
      style: TextStyle(fontFamily: exportFlutterFont(d.fontFamily), fontFamilyFallback: exportFlutterFallback(d.fontFamily)),
      child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(
          aspectRatio: pwMm / phMm,
          child: LayoutBuilder(builder: (context, box) {
            final scale = box.maxWidth / pwMm; // px per mm
            final ml = d.page.left * scale, mt = d.page.top * scale;
            final cw = (box.maxWidth - (d.page.left + d.page.right) * scale).clamp(10.0, box.maxWidth);
            final ch = (box.maxHeight - (d.page.top + d.page.bottom) * scale).clamp(10.0, box.maxHeight);
            return Semantics(
              label: t('معاينة الصفحة', 'Page preview'),
              image: true,
              child: Container(
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0x1A1E293B)),
                  boxShadow: [BoxShadow(color: c.textDark.withValues(alpha: .10), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned.fill(child: _PaperDecor(design: d, values: values, scale: scale, content: content, images: images)),
                  for (final b in d.blocks)
                    Positioned(
                      left: ml + b.x * cw,
                      top: mt + b.y * ch,
                      width: b.w * cw,
                      height: b.h * ch,
                      child: IgnorePointer(
                        child: _BlockContent(
                            design: d, dataset: dataset, block: b, values: values, scale: scale, images: images, content: content, placeholders: false),
                      ),
                    ),
                ]),
              ),
            );
          }),
        ),
      ),
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  const _TablePreview({required this.design, required this.dataset, required this.fs, required this.family, this.content});
  final ExportDesign design;
  final ExportDataset dataset;
  final double fs;
  final String family;
  final ExportContent? content;

  @override
  Widget build(BuildContext context) {
    final d = design;
    final cc = content;
    final cols = dataset.columnsFor(d, cc?.columns).where((col) => col.id != cc?.groupBy).toList();
    final rules = cc?.rules ?? const <ExportRule>[];
    final rows = exportVisibleRows(rules, dataset.rows).take(8).toList();
    final headColor = exportColor(d.table.headerColor), onHead = exportColor(d.table.headerTextColor);
    final minimal = d.table.style == 'minimal', grid = d.table.style == 'grid';
    TextStyle st({bool head = false, ExportRuleStyle? look}) => TextStyle(
        fontFamily: family,
        fontSize: fs,
        color: head ? (minimal ? headColor : onHead) : (look?.color != null ? exportColor(look!.color!) : exportColor(d.fontColor)),
        fontWeight: head || (look?.bold ?? false) ? FontWeight.w800 : FontWeight.w500,
        height: 1.2);
    final line = exportColor(exportLine);
    if (cols.isEmpty) return const SizedBox();
    Widget row(List<Widget> cells, {Color? color, Border? border}) => Container(
          decoration: BoxDecoration(color: color, border: border),
          padding: EdgeInsets.symmetric(vertical: fs * .35),
          child: Row(children: cells),
        );
    // the writers' widths (export_layout.dart), in thousandths
    final fractions = exportColumnFractions(d, cols);
    int flex(ExportColumn col) => math.max(1, (fractions[cols.indexOf(col)] * 1000).round());
    String label(ExportColumn col) => _digits(cc?.labels[col.id] ?? col.label(d.lang), cc);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(
        [
          for (final col in cols)
            Expanded(
              flex: flex(col),
              child: Padding(padding: EdgeInsets.symmetric(horizontal: fs * .25), child: Text(label(col), maxLines: 1, overflow: TextOverflow.clip, style: st(head: true))),
            ),
        ],
        color: minimal ? null : headColor,
        border: minimal ? Border(bottom: BorderSide(color: headColor, width: 1.2)) : null,
      ),
      for (var i = 0; i < rows.length; i++)
        () {
          final look = exportRowLook(rules, rows[i]);
          return row(
            [
              for (final col in cols)
                Expanded(
                  flex: flex(col),
                  child: Container(
                    color: look.of(col.id)?.background == null ? null : exportColor(look.of(col.id)!.background!),
                    padding: EdgeInsets.symmetric(horizontal: fs * .25),
                    child: Text(_digits(look.textOf(col.id, dataset.cell(col, rows[i][col.id])), cc),
                        maxLines: 1, overflow: TextOverflow.clip, textAlign: col.numeric ? TextAlign.end : TextAlign.start, style: st(look: look.of(col.id))),
                  ),
                ),
            ],
            color: d.table.style == 'zebra' && i.isOdd ? exportColor('F6F8FA') : null,
            border: grid ? Border.all(color: line, width: .5) : Border(bottom: BorderSide(color: line, width: .5)),
          );
        }(),
      if (rows.isEmpty) Padding(padding: EdgeInsets.all(fs), child: Text(ExportLabels(d.lang).noRows, textAlign: TextAlign.center, style: st().copyWith(color: exportColor(exportMuted)))),
    ]);
  }
}

class _ItemsPreview extends StatelessWidget {
  const _ItemsPreview({required this.design, required this.dataset, required this.pt, required this.family});
  final ExportDesign design;
  final ExportDataset dataset;
  final double Function(double) pt;
  final String family;

  @override
  Widget build(BuildContext context) {
    final d = design;
    final items = dataset.items.isEmpty ? exportSampleItems(d.lang) : dataset.items.take(3).toList();
    final v = d.votes;
    final fs = pt(d.fontSize);
    final line = exportColor(exportLine);
    TextStyle st({double? size, bool bold = false, String? color}) =>
        TextStyle(fontFamily: family, fontSize: size ?? fs, color: exportColor(color ?? d.fontColor), fontWeight: bold ? FontWeight.w800 : FontWeight.w500, height: 1.2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < items.length; i++)
        Container(
          margin: EdgeInsets.only(bottom: fs * .5),
          padding: EdgeInsets.all(fs * .5),
          decoration: BoxDecoration(color: exportColor('FAFBFC'), border: Border.all(color: line, width: .5), borderRadius: BorderRadius.circular(3)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: fs * 1.6,
                height: fs * 1.6,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: exportColor(d.table.headerColor), borderRadius: BorderRadius.circular(3)),
                child: Text('${i + 1}', style: st(size: fs * .85, bold: true, color: d.table.headerTextColor)),
              ),
              SizedBox(width: fs * .5),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text(items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: st(bold: true)),
                  Text([if (items[i].ref.isNotEmpty) items[i].ref, items[i].source(d.lang)].where((s) => s.isNotEmpty).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: st(size: fs * .8, color: exportMuted)),
                ]),
              ),
              if (items[i].votes != null && v.beside) ...[
                SizedBox(width: fs * .6),
                ConstrainedBox(constraints: BoxConstraints(maxWidth: fs * 9), child: VoteResultPreview(votes: v, result: items[i].votes!, lang: d.lang, fontSize: fs, beside: true, family: d.fontFamily)),
              ],
            ]),
            if (items[i].votes != null && v.below) ...[
              SizedBox(height: fs * .4),
              VoteResultPreview(votes: v, result: items[i].votes!, lang: d.lang, fontSize: fs, family: d.fontFamily),
            ],
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Engine adapter
// ═════════════════════════════════════════════════════════════════════════════

/// The engine's view of an ExportDesign: blocks ↔ items in millimetres of the content box. [design] is read through
/// a getter, so restoring a snapshot can swap the whole document.
class ExportStudioAdapter implements StudioAdapter<ExportBlock> {
  ExportStudioAdapter(this._get, this._set);

  final ExportDesign Function() _get;
  final void Function(ExportDesign d) _set;
  final _issued = <String>{};

  ExportDesign get design => _get();

  /// The content box in mm.
  (double, double) get box => design.page.contentMm;

  static StudioResize resizeOf(ExportBlock b) => switch (b.kind) {
        'logo' || 'signature' => StudioResize.aspect,
        'line' => StudioResize.horizontal,
        _ => StudioResize.free,
      };

  StudioItem<ExportBlock> itemOf(ExportBlock b) {
    final (w, h) = box;
    return StudioItem<ExportBlock>(
      id: b.id,
      rect: Rect.fromLTWH(b.x * w, b.y * h, b.w * w, b.h * h),
      payload: b,
      resize: resizeOf(b),
      minSize: Size(.06 * w, (b.kind == 'line' ? .002 : .02) * h),
    );
  }

  @override
  List<StudioItem<ExportBlock>> readItems() => [for (final b in design.blocks) itemOf(b)];

  void _place(ExportBlock b, Rect r) {
    final (w, h) = box;
    b
      ..x = r.left / w
      ..y = r.top / h
      ..w = r.width / w
      ..h = r.height / h
      ..clamp();
  }

  @override
  void writeRects(Map<String, Rect> rects) {
    for (final b in design.blocks) {
      final r = rects[b.id];
      if (r != null) _place(b, r);
    }
  }

  @override
  void addItems(List<StudioItem<ExportBlock>> items) {
    for (final it in items) {
      final b = it.payload;
      // one table / items block per page: copies of them are dropped
      if (b.isFlow && design.blocks.any((x) => x.kind == b.kind)) continue;
      _place(b, it.rect);
      design.blocks.add(b);
    }
    _issued.clear();
  }

  @override
  void removeItems(Set<String> ids) => design.blocks.removeWhere((b) => ids.contains(b.id));

  @override
  void reorder(List<String> ids) {
    final byId = {for (final b in design.blocks) b.id: b};
    final next = [for (final id in ids) ?byId[id]];
    for (final b in design.blocks) {
      if (!ids.contains(b.id)) next.add(b);
    }
    design.blocks
      ..clear()
      ..addAll(next);
  }

  String _newId() {
    var n = design.blocks.length + 1;
    while (design.blocks.any((b) => b.id == 'b$n') || _issued.contains('b$n')) {
      n++;
    }
    _issued.add('b$n');
    return 'b$n';
  }

  @override
  StudioItem<ExportBlock> cloneItem(StudioItem<ExportBlock> item) {
    final b = ExportBlock.fromJson({...item.payload.toJson(), 'id': _newId()}, baseSize: item.payload.font.size);
    return item.copyWith(id: b.id, payload: b);
  }

  @override
  Object snapshot() => design.toJson();

  @override
  void restore(Object snapshot) => _set(ExportDesign.fromJson((snapshot as Map).cast<String, dynamic>()));
}

/// The engine page of a design: the content box in mm at 96 dpi, and the 2 % grid.
StudioPage exportStudioPage(ExportDesign d) {
  final (w, h) = d.page.contentMm;
  return StudioPage(w, h, unitPx: 96 / 25.4);
}

Size exportStudioGrid(ExportDesign d) {
  final (w, h) = d.page.contentMm;
  return Size(w * .02, h * .02);
}

/// The canvas's in-place editor over text block [b] at [scale] px / mm: the block's font, size, weight, colour,
/// alignment, the page's direction and the block's background (the same numbers as _BlockContent).
StudioInlineStyle exportInlineStyle(ExportDesign d, ExportBlock b, double scale) {
  final dir = d.rtl ? TextDirection.rtl : TextDirection.ltr;
  return StudioInlineStyle(
    style: TextStyle(
      fontFamily: exportFlutterFont(b.font.family.isEmpty ? d.fontFamily : b.font.family),
      fontFamilyFallback: exportFlutterFallback(b.font.family.isEmpty ? d.fontFamily : b.font.family),
      fontSize: (b.font.size * .3528 * scale).clamp(2.0, 120.0),
      color: exportColor(b.font.color.isEmpty ? d.fontColor : b.font.color),
      height: d.lineSpacing,
      fontWeight: b.font.bold ? FontWeight.w800 : FontWeight.w500,
    ),
    textAlign: switch (b.align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start },
    textDirection: dir,
    multiline: true,
    padding: b.background.isEmpty ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: 1.6 * scale, vertical: .8 * scale),
    background: b.background.isEmpty ? null : exportColor(b.background),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Designer page
// ═════════════════════════════════════════════════════════════════════════════

class ExportDesignerPage extends StatefulWidget {
  const ExportDesignerPage({
    super.key,
    required this.design,
    required this.dataset,
    required this.module,
    required this.lang,
    required this.onSave,
    this.name = '',
    this.orgId,
    this.content,
    this.askName = true,
    this.saveLabel,
    this.title,
  });

  /// The starting design (copied; the page never mutates it).
  final ExportDesign design;

  /// The data the preview shows; null → a sample dataset of the module.
  final ExportDataset? dataset;
  final String module, lang;

  /// The template name shown in the name field.
  final String name;

  /// Organization for logo / signature uploads (`POST …/orgs/{id}/uploads`); without it images are URLs only.
  final int? orgId;

  /// The flow's table choices (columns, labels, rules, numerals) for the canvas and "Preview PDF".
  final ExportContent? content;

  /// false: no name field (the flow's "Use this design"); [saveLabel] replaces "Save".
  final bool askName;
  final String? saveLabel;
  final String? title;

  /// Called with the design and the name; true pops the page.
  final Future<bool> Function(ExportDesign design, String name) onSave;

  @override
  State<ExportDesignerPage> createState() => _ExportDesignerPageState();
}

class _ExportDesignerPageState extends State<ExportDesignerPage> {
  late ExportDesign _d = widget.design.copy();
  late final ExportDataset _data = widget.dataset ?? exportSampleDataset(widget.module, widget.lang);
  late final _name = TextEditingController(text: widget.name);
  late final ExportStudioAdapter _adapter = ExportStudioAdapter(() => _d, (d) => _d = d);
  late final StudioController<ExportBlock> _ctl = StudioController<ExportBlock>(
    adapter: _adapter,
    page: exportStudioPage(_d),
    grid: exportStudioGrid(_d),
    minSize: const Size(4, 2),
    nudgeStep: 1,
    nudgeBigStep: 5,
    pasteOffset: const Offset(4, 4), // mm
  );
  final _images = <String, Uint8List>{};
  final _focus = FocusNode(debugLabel: 'export-studio');

  /// Below 900 px: the properties panel docked under the page (open / folded), never a modal sheet.
  final _dockOpen = ValueNotifier<bool>(false);
  String _tab = 'page';
  bool _busy = false;

  ExportBlock? get _block {
    final s = _ctl.single;
    return s == null ? null : _d.blocks.where((b) => b.id == s.id).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: the floating assistant tab would cover the side panels
    _ctl.addListener(_onCtl);
  }

  String? _lastSel;
  void _onCtl() {
    final sel = _ctl.single?.id;
    if (sel != _lastSel) {
      _lastSel = sel;
      if (sel != null && _tab != 'element') _tab = 'element';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctl.removeListener(_onCtl);
    _ctl.dispose();
    _name.dispose();
    _focus.dispose();
    _dockOpen.dispose();
    AppAssistant.release();
    super.dispose();
  }

  /// One undoable change of the design (coalesced for steppers / sliders / typing).
  void _edit(String label, VoidCallback fn, {bool coalesce = false}) => _ctl.record(label, fn, coalesce: coalesce);

  /// A page change that moves the content box: the engine's page and grid follow.
  void _editPage(String label, VoidCallback fn, {bool coalesce = false}) {
    _ctl.record(label, fn, coalesce: coalesce);
    _ctl
      ..page = exportStudioPage(_d)
      ..grid = exportStudioGrid(_d)
      ..refresh();
  }

  void _add(String kind) {
    late ExportBlock b;
    _edit('add', () => b = _d.add(kind));
    _ctl.select(b.id);
    _focus.requestFocus();
  }

  // ── images
  /// Picks and uploads an image to the organization; its URL (bytes remembered for the preview), or null.
  Future<String?> _uploadImage() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted || widget.orgId == null) return null;
    final bytes = await f.readAsBytes();
    try {
      final r = await ApiClient().postMultipart('$orgBase/orgs/${widget.orgId}/uploads', fields: const {}, fileField: 'file', fileName: f.name, fileBytes: bytes);
      final url = r is Map ? '${r['url'] ?? ''}' : '';
      if (url.isEmpty) return null;
      rememberExportImage(url, bytes);
      _images[url] = bytes;
      return url;
    } on ApiException catch (e) {
      toast(e.message, error: true);
      return null;
    }
  }

  Future<void> _upload(ExportBlock b) async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    if (widget.orgId == null) return toast(t('الرفع يحتاج مؤسسة مفتوحة — الصق رابط الصورة', 'Uploading needs an open organization — paste the image link'), error: true);
    try {
      final r = await ApiClient().postMultipart('$orgBase/orgs/${widget.orgId}/uploads', fields: const {}, fileField: 'file', fileName: f.name, fileBytes: bytes);
      final url = r is Map ? '${r['url'] ?? ''}' : '';
      if (url.isEmpty || !mounted) return;
      rememberExportImage(url, bytes);
      _images[url] = bytes;
      _edit('image', () => b.url = url);
    } on ApiException catch (e) {
      toast(e.message, error: true);
    }
  }

  // ── output
  Future<void> _previewPdf() async {
    setState(() => _busy = true);
    try {
      final images = {..._images, ...await loadExportImages(_d)};
      final bytes = await exportPdf(_d, _data, widget.content ?? ExportContent(), fonts: await loadExportFonts(_d.fontFamilies), images: images);
      final name = exportFileName(_name.text.trim().isEmpty ? _data.title : _name.text.trim(), 'pdf');
      final path = await saver.dlSaveBytes(bytes, name, 'application/pdf');
      if (path != null) toast(kIsWeb ? '${t('تم تنزيل', 'Downloaded')} ${exportLtr(name)} · ${exportLtr(exportSizeLabel(bytes.length))}' : '${t('حُفظ في', 'Saved to')} $path');
    } catch (e) {
      debugPrint('export preview failed: $e');
      toast(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (widget.askName && _name.text.trim().isEmpty) return toast(t('اكتب اسم القالب', 'Give the template a name'), error: true);
    setState(() => _busy = true);
    final ok = await widget.onSave(_d.copy(), _name.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  // ── build
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      appBar: ScreenAppBar(title: widget.title ?? t('استوديو التصميم', 'Design studio')),
      child: StudioSmallScreenGate(
        onBack: () => Navigator.maybePop(context),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final toolbar = Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
            child: StudioToolbar(
              controller: _ctl,
              leading: [_AddMenu(onAdd: _add, hasTable: _d.tableBlock != null, hasItems: _d.itemsBlock != null, showLabel: box.maxWidth >= 720)],
              trailing: [
                StudioToolButton(icon: Icons.picture_as_pdf_rounded, label: t('معاينة PDF', 'Preview PDF'), showLabel: box.maxWidth >= 1100, onPressed: _busy ? null : _previewPdf),
              ],
            ),
          );
          final canvas = StudioCanvas<ExportBlock>(
            controller: _ctl,
            focusNode: _focus,
            autofocus: wide,
            paperInsets: EdgeInsets.fromLTRB(_d.page.left, _d.page.top, _d.page.right, _d.page.bottom),
            paperBuilder: (context, scale) => _PaperDecor(design: _d, values: _previewValues(_d, _data, widget.content), scale: scale, content: widget.content, images: _images),
            // double click (long-press on touch) on a text block edits it on the page; right click = the context menu
            inlineText: (item) => item.payload.kind == 'text' ? item.payload.text : null,
            inlineStyle: (context, item, scale) => exportInlineStyle(_d, item.payload, scale),
            onInlineCommit: (item, text) => item.payload.text = text,
            onItemDoubleTap: wide ? null : (_) => _dockOpen.value = true,
            itemBuilder: (context, item, selected) => _BlockContent(
              design: _d,
              dataset: _data,
              block: item.payload,
              values: _previewValues(_d, _data, widget.content),
              scale: StudioCanvas.scaleOf(context),
              images: _images,
              content: widget.content,
            ),
          );
          if (wide) {
            return Column(children: [
              toolbar,
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: canvas),
                  Container(
                    width: 360,
                    decoration: BoxDecoration(color: c.cardBg, border: BorderDirectional(start: BorderSide(color: c.divider))),
                    child: Column(children: [
                      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md), child: _panel(context))),
                      Container(
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: _saveRow(context),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]);
          }
          final b = _block;
          final multi = _ctl.selection.length > 1;
          return Column(children: [
            toolbar,
            Expanded(child: ClipRect(child: canvas)),
            StudioDockPanel(
              controller: _ctl,
              open: _dockOpen,
              maxHeight: box.maxHeight,
              semanticLabel: t('خصائص التصميم', 'Design properties'),
              title: b != null
                  ? (exportBlockLabels()[b.kind] ?? b.kind)
                  : (multi ? '${_ctl.selection.length} ${t('عناصر محددة', 'selected')}' : t('الصفحة', 'Page')),
              icon: b != null ? _kindIcon(b.kind) : Icons.description_outlined,
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
                child: _panel(context),
              ),
              footer: Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                child: SafeArea(top: false, child: _saveRow(context)),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _saveRow(BuildContext context) {
    final button = AppPrimaryButton(
      label: widget.saveLabel ?? t('حفظ', 'Save'),
      icon: widget.askName ? Icons.save_rounded : Icons.check_rounded,
      busy: _busy,
      onPressed: _busy ? null : _save,
    );
    if (!widget.askName) return button;
    return LayoutBuilder(builder: (context, box) {
      final field = TextField(
        controller: _name,
        style: appText(14, c: context.colors.textDark),
        decoration: InputDecoration(isDense: true, labelText: t('اسم القالب', 'Template name'), prefixIcon: const Icon(Icons.bookmark_outline_rounded, size: 20)),
      );
      if (box.maxWidth < 300) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, const SizedBox(height: AppSpace.xs), button]);
      return Row(children: [Expanded(child: field), const SizedBox(width: AppSpace.sm), SizedBox(width: 128, child: button)]);
    });
  }

  static IconData _kindIcon(String kind) => switch (kind) {
        'text' => Icons.text_fields_rounded,
        'logo' => Icons.image_outlined,
        'signature' => Icons.draw_outlined,
        'line' => Icons.horizontal_rule_rounded,
        'table' => Icons.table_chart_outlined,
        _ => Icons.view_agenda_outlined,
      };

  // ── panel
  Widget _panel(BuildContext context) {
    final tabs = [
      ('element', Icons.crop_square_rounded, t('العنصر', 'Element')),
      ('page', Icons.description_outlined, t('الصفحة', 'Page')),
      if (_d.tableBlock != null) ('table', Icons.table_chart_outlined, t('الجدول', 'Table')),
      if (_d.itemsBlock != null) ('votes', Icons.how_to_vote_outlined, t('التصويت', 'Votes')),
    ];
    final tab = tabs.any((x) => x.$1 == _tab) ? _tab : 'page';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioSegmented<String>(
        segments: [for (final (id, icon, label) in tabs) StudioSegment(value: id, label: label, icon: tabs.length > 3 ? icon : null)],
        value: tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      const SizedBox(height: AppSpace.xs),
      switch (tab) {
        'page' => _pagePanel(context),
        'table' => _tablePanel(context),
        'votes' => _votesPanel(context),
        _ => _elementPanel(context),
      },
    ]);
  }

  Widget _mmStepper(String label, double fraction, double size, ValueChanged<double> set) => StudioStepper(
        label: label,
        value: (fraction * size * 10).round() / 10,
        max: size,
        step: 1,
        decimals: 1,
        suffix: t('مم', 'mm'),
        onChanged: (mm) => set(mm / size),
      );

  Widget _elementPanel(BuildContext context) {
    final c = context.colors;
    final b = _block;
    if (b == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: AppBanner(
          icon: Icons.touch_app_rounded,
          text: _ctl.selection.length > 1
              ? t('عدة عناصر محددة — استخدم المحاذاة والتوزيع من الشريط.', 'Several elements are selected — use Align and Distribute in the toolbar.')
              : t('اضغط عنصرًا في الصفحة لتعديله، أو أضف عنصرًا من «إضافة».', 'Tap an element on the page to edit it, or add one with “Add”.'),
        ),
      );
    }
    final (cw, ch) = _d.page.contentMm;
    final fonts = [
      StudioFontOption(id: '', label: t('خط الصفحة', 'Page font')),
      for (final e in exportFontLabels().entries) StudioFontOption(id: e.key, label: e.value, family: exportFlutterFont(e.key)),
    ];
    final textual = b.kind == 'text' || b.kind == 'signature';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropSection(
        first: true,
        title: exportBlockLabels()[b.kind] ?? b.kind,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!b.isFlow)
            IconButton(tooltip: t('نسخ', 'Duplicate'), onPressed: _ctl.duplicate, icon: Icon(Icons.copy_rounded, size: 20, color: c.textMedium)),
          IconButton(tooltip: t('حذف', 'Delete'), onPressed: _ctl.deleteSelection, icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger)),
        ]),
        children: [
          if (b.kind == 'text') ...[
            StudioTextProp(
              key: ValueKey('text-${b.id}'),
              label: t('النص', 'Text'),
              value: b.text,
              maxLines: 4,
              onChanged: (v) => _edit('text', () => b.text = v, coalesce: true),
            ),
            StudioPlaceholderChips(
              label: t('أدرج متغيرًا', 'Insert a variable'),
              items: [
                for (final k in [
                  ...const ['title', 'org', 'date', 'rows', 'period', 'exporter', 'dept', 'signer'],
                  for (final k in _data.meta.keys)
                    if (!const ['org', 'dept', 'title', 'period', 'date', 'count', 'signer', 'exporter', 'session', 'council', 'session_date'].contains(k)) 'meta.$k',
                ])
                  StudioPlaceholder(k, exportPlaceholderLabels()[k] ?? k),
              ],
              onInsert: (k) => _edit('text', () => b.text = '${b.text}{{$k}}'),
            ),
          ],
          if (b.isImage) ...[
            StudioTextProp(
              key: ValueKey('url-${b.id}'),
              label: t('رابط الصورة', 'Image link'),
              hint: 'https://…',
              ltr: true,
              value: b.url,
              onChanged: (v) => _edit('image', () => b.url = v.trim(), coalesce: true),
            ),
            if (widget.orgId != null)
              Align(alignment: AlignmentDirectional.centerStart, child: AppPill(icon: Icons.upload_rounded, label: t('رفع صورة', 'Upload an image'), onTap: () => _upload(b))),
          ],
          if (b.kind == 'signature') ...[
            StudioTextProp(key: ValueKey('sname-${b.id}'), label: t('الاسم', 'Name'), hint: '{{signer}}', value: b.name, onChanged: (v) => _edit('signature', () => b.name = v, coalesce: true)),
            StudioTextProp(key: ValueKey('stitle-${b.id}'), label: t('الصفة', 'Title'), value: b.title, onChanged: (v) => _edit('signature', () => b.title = v, coalesce: true)),
          ],
        ],
      ),
      if (textual)
        StudioPropSection(title: t('الخط', 'Font'), children: [
          StudioFontPicker(options: fonts, value: b.font.family, onChanged: (v) => _edit('font', () => b.font.family = v)),
          StudioStepper(label: t('الحجم', 'Size'), value: b.font.size, min: 5, max: 60, step: 1, suffix: 'pt', onChanged: (v) => _edit('size', () => b.font.size = v, coalesce: true)),
          StudioWeightPicker(
            value: b.font.bold ? FontWeight.w700 : FontWeight.w400,
            options: const [FontWeight.w400, FontWeight.w700],
            onChanged: (w) => _edit('weight', () => b.font.weight = w == FontWeight.w700 ? 'bold' : 'normal'),
          ),
          StudioColorField(
            label: t('اللون', 'Colour'),
            allowNone: true,
            swatches: _studioSwatches,
            value: b.font.color.isEmpty ? null : exportColor(b.font.color),
            onChanged: (col) => _edit('colour', () => b.font.color = _hexOfColor(col) ?? '', coalesce: true),
          ),
        ]),
      if (b.kind == 'line')
        StudioPropSection(title: t('الخط الفاصل', 'Rule'), children: [
          StudioColorField(
            label: t('اللون', 'Colour'),
            allowNone: true,
            swatches: _studioSwatches,
            value: b.color.isEmpty ? null : exportColor(b.color),
            onChanged: (col) => _edit('colour', () => b.color = _hexOfColor(col) ?? '', coalesce: true),
          ),
        ]),
      if (!b.isFlow && b.kind != 'line')
        StudioPropSection(title: t('المحاذاة والخلفية', 'Alignment & background'), children: [
          StudioTextAlignPicker(
            options: const [TextAlign.start, TextAlign.center, TextAlign.end],
            value: switch (b.align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start },
            onChanged: (a) => _edit('align', () => b.align = switch (a) { TextAlign.center => 'center', TextAlign.end => 'end', _ => 'start' }),
          ),
          StudioColorField(
            label: t('الخلفية', 'Background'),
            allowNone: true,
            swatches: [..._studioSwatches.take(9), const Color(0xFFF1F5F9), const Color(0xFFE0F2F1), const Color(0xFFFEF3C7)],
            value: b.background.isEmpty ? null : exportColor(b.background),
            onChanged: (col) => _edit('background', () => b.background = _hexOfColor(col) ?? '', coalesce: true),
          ),
        ]),
      StudioPropSection(title: t('الموضع والحجم', 'Position & size'), children: [
        Row(children: [
          Expanded(child: _mmStepper(t('من اليسار', 'From left'), b.x, cw, (f) => _edit('move', () => (b..x = f).clamp(), coalesce: true))),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: _mmStepper(t('من الأعلى', 'From top'), b.y, ch, (f) => _edit('move', () => (b..y = f).clamp(), coalesce: true))),
        ]),
        Row(children: [
          Expanded(child: _mmStepper(t('العرض', 'Width'), b.w, cw, (f) => _edit('resize', () => (b..w = f).clamp(), coalesce: true))),
          const SizedBox(width: AppSpace.xs),
          if (b.kind != 'line') Expanded(child: _mmStepper(t('الارتفاع', 'Height'), b.h, ch, (f) => _edit('resize', () => (b..h = f).clamp(), coalesce: true))) else const Spacer(),
        ]),
      ]),
    ]);
  }

  /// The header / footer variables as chips (the server fills the same names in scheduled runs).
  List<StudioPlaceholder> _variableChips() => [for (final k in exportStudioVariables) StudioPlaceholder(k, exportPlaceholderLabels()[k] ?? k)];

  Widget _pagePanel(BuildContext context) {
    final d = _d;
    final f = d.frame, wm = d.watermark;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropSection(first: true, title: t('الورقة', 'Paper'), children: [
        StudioSegmented<String>(
          segments: [for (final s in exportPageSizes) StudioSegment(value: s, label: s)],
          value: d.page.size,
          onChanged: (v) => _editPage('paper', () => d.page.size = v),
        ),
        StudioSegmented<String>(
          segments: [
            StudioSegment(value: 'portrait', label: t('رأسي', 'Portrait'), icon: Icons.crop_portrait_rounded),
            StudioSegment(value: 'landscape', label: t('أفقي', 'Landscape'), icon: Icons.crop_landscape_rounded),
          ],
          value: d.page.orientation,
          onChanged: (v) => _editPage('orientation', () => d.page.orientation = v),
        ),
        Row(children: [
          Expanded(child: StudioStepper(label: t('أعلى', 'Top'), value: d.page.top, max: 60, suffix: t('مم', 'mm'), onChanged: (v) => _editPage('margins', () => d.page.top = v, coalesce: true))),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: StudioStepper(label: t('أسفل', 'Bottom'), value: d.page.bottom, max: 60, suffix: t('مم', 'mm'), onChanged: (v) => _editPage('margins', () => d.page.bottom = v, coalesce: true))),
        ]),
        Row(children: [
          Expanded(child: StudioStepper(label: t('يسار', 'Left'), value: d.page.left, max: 60, suffix: t('مم', 'mm'), onChanged: (v) => _editPage('margins', () => d.page.left = v, coalesce: true))),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: StudioStepper(label: t('يمين', 'Right'), value: d.page.right, max: 60, suffix: t('مم', 'mm'), onChanged: (v) => _editPage('margins', () => d.page.right = v, coalesce: true))),
        ]),
        AppSwitchTile(title: t('من اليمين إلى اليسار', 'Right to left'), value: d.rtl, dense: true, onChanged: (v) => _edit('direction', () => d.rtl = v)),
      ]),
      StudioPropSection(title: t('الخط الأساسي', 'Base font'), children: [
        StudioFontPicker(
          options: [for (final e in exportFontLabels().entries) StudioFontOption(id: e.key, label: e.value, family: exportFlutterFont(e.key))],
          value: d.fontFamily,
          onChanged: (v) => _edit('font', () => d.fontFamily = v),
        ),
        StudioStepper(label: t('الحجم', 'Size'), value: d.fontSize, min: 6, max: 30, suffix: 'pt', onChanged: (v) => _edit('size', () => d.fontSize = v, coalesce: true)),
        StudioColorField(label: t('اللون', 'Colour'), swatches: _studioSwatches, value: exportColor(d.fontColor), onChanged: (col) => _edit('colour', () => d.fontColor = _hexOfColor(col) ?? exportInk, coalesce: true)),
      ]),
      StudioPropSection(title: t('رأس الصفحة وتذييلها', 'Header & footer'), children: [
        StudioTextProp(key: const ValueKey('header'), label: t('نص الرأس', 'Header text'), hint: '{{org_name}}', value: d.headerText, onChanged: (v) => _edit('header', () => d.headerText = v, coalesce: true)),
        StudioPlaceholderChips(label: t('أدرج متغيرًا', 'Insert a variable'), items: _variableChips(), onInsert: (k) => _edit('header', () => d.headerText = '${d.headerText}{{$k}}')),
        AppSwitchTile(title: t('التاريخ في الرأس', 'Date in the header'), value: d.showDate, dense: true, onChanged: (v) => _edit('header', () => d.showDate = v)),
        StudioTextProp(key: const ValueKey('footer'), label: t('نص التذييل', 'Footer text'), hint: '{{page}} / {{pages}}', value: d.footerText, onChanged: (v) => _edit('footer', () => d.footerText = v, coalesce: true)),
        StudioPlaceholderChips(label: t('أدرج متغيرًا', 'Insert a variable'), items: _variableChips(), onInsert: (k) => _edit('footer', () => d.footerText = '${d.footerText}{{$k}}')),
        AppSwitchTile(title: t('أرقام الصفحات', 'Page numbers'), value: d.showPageNumbers, dense: true, onChanged: (v) => _edit('footer', () => d.showPageNumbers = v)),
      ]),
      StudioPropSection(title: t('إطار الصفحة', 'Page frame'), children: [
        StudioSegmented<String>(
          segments: [
            StudioSegment(value: 'none', label: t('بلا', 'None')),
            StudioSegment(value: 'solid', label: t('متصل', 'Solid')),
            StudioSegment(value: 'dashed', label: t('متقطع', 'Dashed')),
            StudioSegment(value: 'double', label: t('مزدوج', 'Double')),
          ],
          value: f.style,
          onChanged: (v) => _edit('frame', () => f.style = v),
        ),
        if (f.visible) ...[
          Row(children: [
            Expanded(child: StudioStepper(label: t('السُمك', 'Width'), value: f.width, min: .25, max: 12, step: .25, decimals: 2, suffix: 'pt', onChanged: (v) => _edit('frame', () => f.width = v, coalesce: true))),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: StudioStepper(label: t('الزوايا', 'Corners'), value: f.radius, max: 40, suffix: 'pt', onChanged: (v) => _edit('frame', () => f.radius = v, coalesce: true))),
          ]),
          StudioStepper(label: t('البعد عن المحتوى', 'Distance from the content'), value: f.inset, max: 30, suffix: t('مم', 'mm'), onChanged: (v) => _edit('frame', () => f.inset = v, coalesce: true)),
          StudioColorField(label: t('اللون', 'Colour'), swatches: _studioSwatches, value: exportColor(f.color), onChanged: (col) => _edit('frame', () => f.color = _hexOfColor(col) ?? exportLine, coalesce: true)),
        ],
      ]),
      StudioPropSection(title: t('العلامة المائية', 'Watermark'), children: [
        ExportWatermarkEditor(
          key: const ValueKey('wm'),
          mark: wm,
          onEdit: (change) => _edit('watermark', change, coalesce: true),
          onUpload: widget.orgId == null ? null : _uploadImage,
        ),
      ]),
    ]);
  }

  Widget _tablePanel(BuildContext context) {
    final d = _d;
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropSection(first: true, title: t('النمط', 'Style'), children: [
        StudioSegmented<String>(
          segments: [for (final e in exportTableStyleLabels().entries) StudioSegment(value: e.key, label: e.value)],
          value: d.table.style,
          onChanged: (v) => _edit('table', () => d.table.style = v),
        ),
        StudioStepper(label: t('حجم الخط', 'Font size'), value: d.table.fontSize, min: 5, max: 24, suffix: 'pt', onChanged: (v) => _edit('table', () => d.table.fontSize = v, coalesce: true)),
        StudioColorField(
          label: t('لون الرأس', 'Header colour'),
          swatches: _studioSwatches,
          value: exportColor(d.table.headerColor),
          onChanged: (col) => _edit('table', () {
            d.table.headerColor = _hexOfColor(col) ?? exportBrand;
            d.table.headerTextColor = ['FFFFFF', 'F6F8FA'].contains(d.table.headerColor) ? exportInk : 'FFFFFF';
          }, coalesce: true),
        ),
        StudioColorField(
          label: t('لون نص الرأس', 'Header text colour'),
          swatches: _studioSwatches,
          value: exportColor(d.table.headerTextColor),
          onChanged: (col) => _edit('table', () => d.table.headerTextColor = _hexOfColor(col) ?? 'FFFFFF', coalesce: true),
        ),
      ]),
      if (widget.content == null)
        StudioPropSection(title: t('الأعمدة', 'Columns'), children: [
          if (_data.columns.isEmpty)
            Text(t('لا أعمدة في هذه البيانات', 'This data has no columns'), style: appText(12, c: c.textMedium))
          else
            for (final col in _data.columns)
              AppSwitchTile(
                title: col.label(d.lang),
                dense: true,
                value: d.table.columns.isEmpty || d.table.columns.contains(col.id),
                onChanged: (v) => _edit('columns', () {
                  final cur = d.table.columns.isEmpty ? [for (final x in _data.columns) x.id] : [...d.table.columns];
                  if (v) {
                    if (!cur.contains(col.id)) cur.add(col.id);
                  } else {
                    cur.remove(col.id);
                  }
                  d.table.columns = [for (final x in _data.columns) if (cur.contains(x.id)) x.id];
                }),
              ),
        ])
      else
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: AppBanner(icon: Icons.view_column_outlined, text: t('الأعمدة وأسماؤها تُختار في خطوة «الحقول».', 'Columns and their names are chosen in the “Fields” step.')),
        ),
    ]);
  }

  Widget _votesPanel(BuildContext context) {
    final v = _d.votes;
    final sample = exportSampleItems(_d.lang).first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropSection(first: true, title: t('موضع النتيجة', 'Result position'), children: [
        StudioSegmented<String>(
          segments: [for (final e in exportVotePositionLabels().entries) StudioSegment(value: e.key, label: e.value)],
          value: v.position,
          onChanged: (x) => _edit('votes', () => v.position = x),
        ),
        StudioSegmented<String>(
          segments: [for (final e in exportVoteStyleLabels().entries) StudioSegment(value: e.key, label: e.value)],
          value: v.style,
          onChanged: (x) => _edit('votes', () => v.style = x),
        ),
        AppSwitchTile(title: t('الأعداد', 'Counts'), value: v.showCounts, dense: true, onChanged: (x) => _edit('votes', () => v.showCounts = x)),
        AppSwitchTile(title: t('النسبة', 'Percent'), value: v.showPercent, dense: true, onChanged: (x) => _edit('votes', () => v.showPercent = x)),
        AppSwitchTile(title: t('النتيجة', 'Outcome'), value: v.showOutcome, dense: true, onChanged: (x) => _edit('votes', () => v.showOutcome = x)),
        AppSwitchTile(title: t('أسماء المصوّتين', 'Voters'), value: v.showVoters, dense: true, onChanged: (x) => _edit('votes', () => v.showVoters = x)),
      ]),
      StudioPropSection(title: t('عينة', 'Sample'), children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: _paper, borderRadius: AppRadius.chipAll, border: Border.all(color: context.colors.divider)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(sample.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: exportFlutterFont(_d.fontFamily), fontSize: 12, fontWeight: FontWeight.w800, color: exportColor(_d.fontColor))),
                if (v.below) ...[const SizedBox(height: 6), VoteResultPreview(votes: v, result: sample.votes!, lang: _d.lang, fontSize: 11, family: _d.fontFamily)],
              ]),
            ),
            if (v.beside) ...[
              const SizedBox(width: 8),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 110), child: VoteResultPreview(votes: v, result: sample.votes!, lang: _d.lang, fontSize: 11, beside: true, family: _d.fontFamily)),
            ],
          ]),
        ),
      ]),
    ]);
  }
}

/// "Add" in the toolbar: text · logo · signature · line · (table) · (items).
class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.onAdd, required this.hasTable, required this.hasItems, required this.showLabel});
  final ValueChanged<String> onAdd;
  final bool hasTable, hasItems, showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kinds = [
      ('text', Icons.text_fields_rounded),
      ('logo', Icons.image_outlined),
      ('signature', Icons.draw_outlined),
      ('line', Icons.horizontal_rule_rounded),
      if (!hasTable) ('table', Icons.table_chart_outlined),
      if (!hasItems) ('items', Icons.view_agenda_outlined),
    ];
    return PopupMenuButton<String>(
      tooltip: t('إضافة عنصر', 'Add an element'),
      onSelected: onAdd,
      itemBuilder: (context) => [
        for (final (kind, icon) in kinds)
          PopupMenuItem<String>(
            value: kind,
            child: Row(children: [
              Icon(icon, size: 20, color: c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: Text(exportBlockLabels()[kind] ?? kind, style: appText(14, c: c.textDark))),
            ]),
          ),
      ],
      child: StudioToolFace(icon: Icons.add_box_outlined, label: t('إضافة', 'Add'), showLabel: showLabel, trailingIcon: Icons.expand_more_rounded),
    );
  }
}

/// A text property that keeps its own controller (typing is not reset by rebuilds).
