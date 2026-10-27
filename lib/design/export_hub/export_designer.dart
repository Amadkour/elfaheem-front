// lib/design/export_hub/export_designer.dart
//
// The Export Hub's visual designer: a page canvas with the live preview (blocks at their fractions, drag to move,
// a corner handle to resize, snapping to a 2 % grid), and the settings of the selected block / the page / the
// table / the votes layout in a side panel (wide) or a bottom sheet (phone). "Preview PDF" renders the real file
// through export_pdf.dart and saves / shares it like every export. Undo keeps a small history of the design.
//
//     ExportDesignerPage(design: d, dataset: ds, module: 'council', lang: 'ar', onSave: (design, name) async {…})
//
// `ExportPagePreview` and `VoteResultPreview` take plain values and are what the layout harness pumps
// (test/ui/export_hub_layout_test.dart). Pure model: export_design.dart.
library;

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
import '../../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../app_kit.dart';
import 'export_design.dart';
import 'export_pdf.dart';

// The page preview is the printed sheet: paper and ink are document colours, not theme colours.
const _paper = Color(0xFFFFFFFF);

Color exportColor(String hex, [Color fallback = const Color(0xFF1E293B)]) {
  final h = hexOf(hex, '');
  return h.isEmpty ? fallback : Color(int.parse('FF$h', radix: 16));
}

/// The Flutter font family of a design family (pubspec: tajawal · bahji · PaperPlex).
String exportFlutterFont(String family) => switch (family) { 'bahij' => 'bahji', 'plex' => 'PaperPlex', _ => 'tajawal' };

/// Swatches offered for text, lines and the table header.
const exportSwatches = ['1E293B', '64748B', '0F766E', '1E40AF', '7C3AED', '991B1B', '92400E', '166534', '000000', 'FFFFFF'];

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
    final cached = _imageCache[b.url];
    if (cached != null) {
      out[b.url] = cached;
      continue;
    }
    try {
      final res = await http.get(Uri.parse(orgFileUrl(b.url))).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) out[b.url] = _imageCache[b.url] = res.bodyBytes;
    } catch (_) {}
  }
  return out;
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
//  Page preview (presentational)
// ═════════════════════════════════════════════════════════════════════════════

/// The designed page at any width: the paper, the margin guide, every block at its fractions. Interactive when
/// [onSelect] is given (tap, drag to move, corner handle to resize); read-only otherwise (the hub's preview).
class ExportPagePreview extends StatelessWidget {
  const ExportPagePreview({
    super.key,
    required this.design,
    required this.dataset,
    this.selectedId,
    this.onSelect,
    this.onMove,
    this.onResize,
    this.onDragStart,
    this.onDragEnd,
    this.maxWidth = 620,
    this.images,
  });

  final ExportDesign design;
  final ExportDataset dataset;
  final String? selectedId;
  final ValueChanged<String?>? onSelect;

  /// Deltas as fractions of the content box.
  final void Function(ExportBlock b, double dx, double dy)? onMove, onResize;
  final VoidCallback? onDragStart, onDragEnd;
  final double maxWidth;

  /// Image bytes by URL (uploaded this session); the rest load from the network.
  final Map<String, Uint8List>? images;

  bool get interactive => onSelect != null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = design;
    final (pwMm, phMm) = d.page.mm;
    final values = dataset.placeholderValues(d.lang);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(
          aspectRatio: pwMm / phMm,
          child: LayoutBuilder(builder: (context, box) {
            final scale = box.maxWidth / pwMm; // px per mm
            final ml = d.page.left * scale, mt = d.page.top * scale;
            final cw = (box.maxWidth - (d.page.left + d.page.right) * scale).clamp(10.0, box.maxWidth);
            final ch = (box.maxHeight - (d.page.top + d.page.bottom) * scale).clamp(10.0, box.maxHeight);
            return GestureDetector(
              onTap: onSelect == null ? null : () => onSelect!(null),
              child: Container(
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [BoxShadow(color: c.textDark.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned(
                    left: ml,
                    top: mt,
                    width: cw,
                    height: ch,
                    child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.divider.withValues(alpha: .7), width: .6)))),
                  ),
                  if (d.headerText.trim().isNotEmpty || d.showDate)
                    Positioned(
                      left: ml,
                      right: ml,
                      top: (mt * .4).clamp(2, mt),
                      child: IgnorePointer(child: _hf(fillPlaceholders(d.headerText, values).replaceAll('{{page}}', '1').replaceAll('{{pages}}', '1'), d.showDate ? values['date'] ?? '' : '', scale)),
                    ),
                  if (d.footerText.trim().isNotEmpty || d.showPageNumbers)
                    Positioned(
                      left: ml,
                      right: ml,
                      bottom: (d.page.bottom * scale * .35).clamp(2, mt),
                      child: IgnorePointer(child: _hf(fillPlaceholders(d.footerText, values).replaceAll('{{page}}', '1').replaceAll('{{pages}}', '1'), d.showPageNumbers ? '1 / 1' : '', scale)),
                    ),
                  for (final b in d.blocks)
                    Positioned(
                      left: ml + b.x * cw,
                      top: mt + b.y * ch,
                      width: b.w * cw,
                      height: b.h * ch,
                      child: _PreviewBlock(preview: this, block: b, values: values, scale: scale, cw: cw, ch: ch),
                    ),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _hf(String start, String end, double scale) {
    final st = TextStyle(fontFamily: exportFlutterFont(design.fontFamily), fontSize: (design.fontSize * .78 * .3528 * scale).clamp(4, 40), color: exportColor(exportMuted));
    return Row(children: [
      Expanded(child: Text(start, maxLines: 1, overflow: TextOverflow.ellipsis, style: st)),
      if (end.isNotEmpty) Text(end, maxLines: 1, style: st),
    ]);
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({required this.preview, required this.block, required this.values, required this.scale, required this.cw, required this.ch});
  final ExportPagePreview preview;
  final ExportBlock block;
  final Map<String, String> values;
  final double scale, cw, ch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = preview.design;
    final b = block;
    final rtl = d.rtl;
    final sel = b.id == preview.selectedId;
    // 1 pt = 0.3528 mm on paper
    double pt(double size) => (size * .3528 * scale).clamp(3.0, 80.0);
    final family = exportFlutterFont(b.font.family.isEmpty ? d.fontFamily : b.font.family);
    final ta = switch (b.align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start };
    final al = switch (b.align) { 'center' => Alignment.topCenter, 'end' => AlignmentDirectional.topEnd, _ => AlignmentDirectional.topStart };
    final ink = b.font.color.isEmpty ? d.fontColor : b.font.color;
    TextStyle st({double? size, bool? bold, String? color}) => TextStyle(
        fontFamily: family, fontSize: pt(size ?? b.font.size), color: exportColor(color ?? ink), height: d.lineSpacing, fontWeight: (bold ?? b.font.bold) ? FontWeight.w800 : FontWeight.w500);
    Widget content;
    switch (b.kind) {
      case 'table':
        content = _TablePreview(design: d, dataset: preview.dataset, fs: pt(d.table.fontSize), family: exportFlutterFont(d.fontFamily));
      case 'items':
        content = _ItemsPreview(design: d, dataset: preview.dataset, pt: pt, family: exportFlutterFont(d.fontFamily));
      case 'logo':
        content = _netImage(b.url, Icons.image_rounded, t('الشعار', 'Logo'), al);
      case 'signature':
        final name = fillPlaceholders(b.name, values).trim(), title = fillPlaceholders(b.title, values).trim();
        content = Column(children: [
          Expanded(child: _netImage(b.url, Icons.draw_rounded, t('التوقيع', 'Signature'), al)),
          if (name.isNotEmpty) Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: ta, style: st(bold: true)),
          if (title.isNotEmpty) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: ta, style: st(size: b.font.size * .85, bold: false, color: exportMuted)),
        ]);
      case 'line':
        content = Align(alignment: Alignment.topCenter, child: Container(height: (b.h * ch).clamp(.5, 6), color: exportColor(b.color.isEmpty ? exportLine : b.color)));
      default:
        content = Align(
          alignment: al,
          child: Text(fillPlaceholders(b.text, values), textAlign: ta, overflow: TextOverflow.fade, style: st()),
        );
    }
    final body = Container(
      decoration: BoxDecoration(
        border: Border.all(color: sel ? c.primary : Colors.transparent, width: sel ? 1.4 : 1),
        color: sel ? c.primary.withValues(alpha: .05) : null,
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: ClipRect(child: content)),
        if (sel && preview.onResize != null)
          PositionedDirectional(
            end: -7,
            bottom: -7,
            child: GestureDetector(
              onPanStart: (_) => preview.onDragStart?.call(),
              onPanUpdate: (e) => preview.onResize!(b, (rtl ? -e.delta.dx : e.delta.dx) / cw, e.delta.dy / ch),
              onPanEnd: (_) => preview.onDragEnd?.call(),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: _paper, width: 2)),
              ),
            ),
          ),
      ]),
    );
    if (!preview.interactive) return IgnorePointer(child: body);
    return GestureDetector(
      onTap: () => preview.onSelect!(b.id),
      onPanStart: (_) {
        preview.onSelect!(b.id);
        preview.onDragStart?.call();
      },
      onPanUpdate: preview.onMove == null ? null : (e) => preview.onMove!(b, e.delta.dx / cw, e.delta.dy / ch),
      onPanEnd: (_) => preview.onDragEnd?.call(),
      child: body,
    );
  }

  Widget _netImage(String url, IconData icon, String label, AlignmentGeometry al) {
    final cached = preview.images?[url] ?? cachedExportImage(url);
    if (cached != null) return Align(alignment: al, child: Image.memory(cached, fit: BoxFit.contain));
    if (url.isNotEmpty) return Align(alignment: al, child: Image.network(orgFileUrl(url), fit: BoxFit.contain, errorBuilder: (_, _, _) => _placeholder(icon, label)));
    return _placeholder(icon, label);
  }

  Widget _placeholder(IconData icon, String label) {
    final ink = exportColor(exportInk);
    return DecoratedBox(
      decoration: BoxDecoration(color: ink.withValues(alpha: .04), borderRadius: BorderRadius.circular(4)),
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: ink.withValues(alpha: .4)),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .5))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  const _TablePreview({required this.design, required this.dataset, required this.fs, required this.family});
  final ExportDesign design;
  final ExportDataset dataset;
  final double fs;
  final String family;

  @override
  Widget build(BuildContext context) {
    final d = design;
    final cols = dataset.columnsFor(d);
    final rows = dataset.rows.take(6).toList();
    final headColor = exportColor(d.table.headerColor), onHead = exportColor(d.table.headerTextColor);
    final minimal = d.table.style == 'minimal', grid = d.table.style == 'grid';
    TextStyle st({bool head = false}) =>
        TextStyle(fontFamily: family, fontSize: fs, color: head ? (minimal ? headColor : onHead) : exportColor(d.fontColor), fontWeight: head ? FontWeight.w800 : FontWeight.w500, height: 1.2);
    final line = exportColor(exportLine);
    if (cols.isEmpty) return const SizedBox();
    Widget row(List<Widget> cells, {Color? color, Border? border}) => Container(
          decoration: BoxDecoration(color: color, border: border),
          padding: EdgeInsets.symmetric(vertical: fs * .35, horizontal: fs * .2),
          child: Row(children: cells),
        );
    int flex(ExportColumn col) => col.id == 'n' ? 1 : col.numeric ? 2 : (col.id == 'title' || col.id == 'subject' || col.id == 'body' ? 5 : 3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(
        [for (final col in cols) Expanded(flex: flex(col), child: Text(col.label(d.lang), maxLines: 1, overflow: TextOverflow.clip, style: st(head: true)))],
        color: minimal ? null : headColor,
        border: minimal ? Border(bottom: BorderSide(color: headColor, width: 1.2)) : null,
      ),
      for (var i = 0; i < rows.length; i++)
        row(
          [for (final col in cols) Expanded(flex: flex(col), child: Text(dataset.cell(col, rows[i][col.id]), maxLines: 1, overflow: TextOverflow.clip, style: st()))],
          color: d.table.style == 'zebra' && i.isOdd ? exportColor('F6F8FA') : null,
          border: grid ? Border.all(color: line, width: .5) : Border(bottom: BorderSide(color: line, width: .5)),
        ),
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

  /// Called with the design and the name; true pops the page.
  final Future<bool> Function(ExportDesign design, String name) onSave;

  @override
  State<ExportDesignerPage> createState() => _ExportDesignerPageState();
}

class _ExportDesignerPageState extends State<ExportDesignerPage> {
  late ExportDesign _d = widget.design.copy();
  late final ExportDataset _data = widget.dataset ?? exportSampleDataset(widget.module, widget.lang);
  late final _name = TextEditingController(text: widget.name);
  late final _header = TextEditingController(text: _d.headerText);
  late final _footer = TextEditingController(text: _d.footerText);
  final _text = TextEditingController(), _url = TextEditingController(), _signer = TextEditingController(), _title = TextEditingController();
  final _history = <Map<String, dynamic>>[];
  final _images = <String, Uint8List>{};
  String? _selected;
  String _tab = 'block';
  bool _busy = false, _dragging = false;

  ExportBlock? get _block => _d.blocks.where((b) => b.id == _selected).firstOrNull;

  @override
  void dispose() {
    for (final c in [_name, _header, _footer, _text, _url, _signer, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── history
  void _push() {
    _history.add(_d.toJson());
    if (_history.length > 40) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _d = ExportDesign.fromJson(_history.removeLast());
      if (_block == null) _selected = null;
      _syncControllers();
    });
  }

  /// A change of the design: snapshot first, then apply.
  void _edit(void Function() fn) => setState(() {
        _push();
        fn();
      });

  void _select(String? id) => setState(() {
        _selected = id;
        if (id != null) _tab = 'block';
        _syncControllers();
      });

  void _syncControllers() {
    final b = _block;
    void set(TextEditingController c, String v) {
      if (c.text != v) c.text = v;
    }

    set(_text, b?.text ?? '');
    set(_url, b?.url ?? '');
    set(_signer, b?.name ?? '');
    set(_title, b?.title ?? '');
    set(_header, _d.headerText);
    set(_footer, _d.footerText);
  }

  // ── canvas callbacks
  void _dragStart() {
    if (_dragging) return;
    _dragging = true;
    _push();
  }

  void _dragEnd() {
    _dragging = false;
    final b = _block;
    if (b != null) setState(() => b.snap());
  }

  void _move(ExportBlock b, double dx, double dy) => setState(() {
        b.x += dx;
        b.y += dy;
        b.clamp();
      });

  void _resize(ExportBlock b, double dw, double dh) => setState(() {
        b.w += dw;
        b.h += dh;
        b.clamp();
      });

  // ── images
  Future<void> _upload() async {
    final b = _block;
    if (b == null || !b.isImage) return;
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    if (widget.orgId == null) return toast(t('الرفع يحتاج مؤسسة مفتوحة', 'Uploading needs an open organization'), error: true);
    try {
      final r = await ApiClient().postMultipart('$orgBase/orgs/${widget.orgId}/uploads', fields: const {}, fileField: 'file', fileName: f.name, fileBytes: bytes);
      final url = r is Map ? '${r['url'] ?? ''}' : '';
      if (url.isEmpty || !mounted) return;
      rememberExportImage(url, bytes);
      _images[url] = bytes;
      _edit(() => b.url = url);
      _syncControllers();
    } on ApiException catch (e) {
      toast(e.message, error: true);
    }
  }

  // ── output
  Future<void> _previewPdf() async {
    setState(() => _busy = true);
    try {
      final images = {..._images, ...await loadExportImages(_d)};
      final bytes = await exportPdf(_d, _data, ExportContent(), fonts: await loadExportFonts(_d.fontFamilies), images: images);
      final name = (_name.text.trim().isEmpty ? _data.title : _name.text.trim()).replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_');
      final path = await saver.dlSaveBytes(bytes, '$name.pdf', 'application/pdf');
      if (path != null) toast(kIsWeb ? t('تم تنزيل الملف', 'File downloaded') : '${t('حُفظ في', 'Saved to')} $path');
    } catch (e) {
      debugPrint('export preview failed: $e');
      toast(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(t('اكتب اسم القالب', 'Give the template a name'), error: true);
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
      appBar: ScreenAppBar(
        title: t('مصمم التصدير', 'Export designer'),
        actions: [
          IconButton(tooltip: t('تراجع', 'Undo'), onPressed: _history.isEmpty ? null : _undo, icon: const Icon(Icons.undo_rounded)),
          IconButton(tooltip: t('معاينة PDF', 'Preview PDF'), onPressed: _busy ? null : _previewPdf, icon: const Icon(Icons.picture_as_pdf_rounded)),
        ],
      ),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 920;
        final canvas = _canvas(context);
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 8, 24), child: canvas)),
            SizedBox(
              width: 360,
              child: Column(children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(8, 12, 16, 12), child: _panel(context))),
                Padding(padding: const EdgeInsets.fromLTRB(8, 0, 16, 16), child: _saveRow(context)),
              ]),
            ),
          ]);
        }
        return Column(children: [
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: canvas)),
          Container(
            decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                AppPill(icon: Icons.tune_rounded, label: _block == null ? t('الصفحة', 'Page') : t('العنصر', 'Block'), onTap: () => _openPanelSheet(context)),
                AppPill(icon: Icons.table_chart_rounded, label: t('الجدول', 'Table'), onTap: () => _openPanelSheet(context, tab: 'table')),
                AppPill(icon: Icons.how_to_vote_rounded, label: t('التصويت', 'Votes'), onTap: () => _openPanelSheet(context, tab: 'votes')),
              ]),
              const SizedBox(height: 10),
              _saveRow(context),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _saveRow(BuildContext context) => Row(children: [
        Expanded(
          child: TextField(
            controller: _name,
            style: appText(14, c: context.colors.textDark),
            decoration: InputDecoration(isDense: true, hintText: t('اسم القالب', 'Template name'), prefixIcon: const Icon(Icons.bookmark_outline_rounded, size: 20)),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _save)),
      ]);

  Widget _canvas(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (kind, icon) in [
          ('text', Icons.text_fields_rounded),
          ('logo', Icons.image_rounded),
          ('signature', Icons.draw_rounded),
          ('line', Icons.horizontal_rule_rounded),
          if (_d.tableBlock == null) ('table', Icons.table_chart_rounded),
          if (_d.itemsBlock == null) ('items', Icons.view_agenda_rounded),
        ])
          AppPill(icon: icon, label: '+ ${exportBlockLabels()[kind]}', onTap: () => _edit(() => _selected = _d.add(kind).id)),
      ]),
      const SizedBox(height: 10),
      ExportPagePreview(
        design: _d,
        dataset: _data,
        selectedId: _selected,
        images: _images,
        onSelect: _select,
        onMove: _move,
        onResize: _resize,
        onDragStart: _dragStart,
        onDragEnd: _dragEnd,
      ),
      const SizedBox(height: 6),
      Text(t('اسحب أي عنصر لتحريكه، واسحب الزاوية لتغيير حجمه، واضغط عليه لتعديله. تُثبَّت المواضع على شبكة 2٪.', 'Drag a block to move it, drag its corner to resize, tap it to edit. Positions snap to a 2% grid.'),
          textAlign: TextAlign.center, style: appText(11.5, c: c.textLight)),
    ]);
  }

  Future<void> _openPanelSheet(BuildContext context, {String? tab}) async {
    setState(() => _tab = tab ?? (_block == null ? 'page' : 'block'));
    await showAppSheet<void>(
      context,
      (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(t('إعدادات التصميم', 'Design settings')),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: _panel(ctx, refresh: () => set(() {})),
            ),
          ),
        ]);
      }),
    );
  }

  // ── panel
  Widget _panel(BuildContext context, {VoidCallback? refresh}) {
    void change(void Function() fn) {
      _edit(fn);
      refresh?.call();
    }

    final tabs = [
      ('block', Icons.crop_square_rounded, t('العنصر', 'Block')),
      ('page', Icons.description_outlined, t('الصفحة', 'Page')),
      ('table', Icons.table_chart_outlined, t('الجدول', 'Table')),
      ('votes', Icons.how_to_vote_outlined, t('التصويت', 'Votes')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, icon, label) in tabs)
          AppChoiceChip(
              label: label,
              icon: icon,
              selected: _tab == id,
              onTap: () {
                setState(() => _tab = id);
                refresh?.call();
              }),
      ]),
      const SizedBox(height: 12),
      switch (_tab) {
        'page' => _pagePanel(context, change),
        'table' => _tablePanel(context, change),
        'votes' => _votesPanel(context, change),
        _ => _blockPanel(context, change),
      },
    ]);
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(title, style: appText(12.5, w: FontWeight.w800, c: context.colors.textMedium)),
      );

  Widget _chips<T>(Map<T, String> options, T value, ValueChanged<T> onPick) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in options.entries) AppChoiceChip(label: e.value, selected: e.key == value, onTap: () => onPick(e.key)),
      ]);

  Widget _slider(BuildContext context, String label, double value, double min, double max, ValueChanged<double> onChanged, {String Function(double)? fmt}) {
    final c = context.colors;
    return Row(children: [
      SizedBox(width: 92, child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium))),
      Expanded(child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 40, child: Text(fmt?.call(value) ?? value.toStringAsFixed(0), textAlign: TextAlign.end, style: appText(12, w: FontWeight.w700, c: c.textDark))),
    ]);
  }

  Widget _swatches(String value, ValueChanged<String> onPick, {bool allowDefault = false}) {
    final c = context.colors;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (allowDefault)
        _Swatch(color: null, selected: value.isEmpty, onTap: () => onPick(''), label: t('افتراضي', 'Default')),
      for (final hex in exportSwatches) _Swatch(color: exportColor(hex), selected: value.toUpperCase() == hex, onTap: () => onPick(hex), border: c.divider),
    ]);
  }

  Widget _blockPanel(BuildContext context, void Function(void Function()) change) {
    final c = context.colors;
    final b = _block;
    if (b == null) {
      return AppBanner(icon: Icons.touch_app_rounded, text: t('اضغط على عنصر في الصفحة لتعديله، أو أضف عنصرًا من الأزرار أعلى الصفحة.', 'Tap a block on the page to edit it, or add one from the buttons above the page.'));
    }
    final fontOptions = {'': t('خط الصفحة', 'Page font'), ...exportFontLabels()};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(exportBlockLabels()[b.kind] ?? b.kind, style: appText(14, w: FontWeight.w800, c: c.textDark))),
        if (!b.isFlow)
          IconButton(
              tooltip: t('نسخ', 'Duplicate'),
              onPressed: () => change(() {
                    final copy = ExportBlock.fromJson({...b.toJson(), 'id': _d.nextId(), 'y': b.y + .04});
                    _d.blocks.add(copy);
                    _selected = copy.id;
                  }),
              icon: const Icon(Icons.copy_rounded, size: 20)),
        IconButton(
            tooltip: t('حذف', 'Delete'),
            onPressed: () => change(() {
                  _d.remove(b.id);
                  _selected = null;
                }),
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger)),
      ]),
      if (b.kind == 'text') ...[
        AppField(controller: _text, label: t('النص', 'Text'), maxLines: 3, onChanged: (v) => change(() => b.text = v)),
        Text(t('أدرج حقلًا:', 'Insert a field:'), style: appText(11.5, c: c.textMedium)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in exportPlaceholderLabels().entries)
            if (e.key != 'page' && e.key != 'pages')
              AppChoiceChip(
                  label: e.value,
                  selected: false,
                  onTap: () {
                    final sel = _text.selection;
                    final at = sel.isValid ? sel.start : _text.text.length;
                    final nt = '${_text.text.substring(0, at)}{{${e.key}}}${_text.text.substring(at)}';
                    _text.text = nt;
                    change(() => b.text = nt);
                  }),
          for (final k in _data.meta.keys)
            if (!const ['org', 'dept', 'title', 'period', 'date', 'count', 'signer', 'session', 'council', 'session_date'].contains(k))
              AppChoiceChip(
                  label: 'meta.$k',
                  selected: false,
                  onTap: () {
                    final nt = '${_text.text}{{meta.$k}}';
                    _text.text = nt;
                    change(() => b.text = nt);
                  }),
        ]),
      ],
      if (b.isImage) ...[
        AppField(controller: _url, label: t('رابط الصورة', 'Image URL'), hint: 'https://…', ltr: true, onChanged: (v) => change(() => b.url = v.trim())),
        if (widget.orgId != null)
          Align(alignment: AlignmentDirectional.centerStart, child: AppPill(icon: Icons.upload_rounded, label: t('رفع صورة', 'Upload image'), onTap: _upload)),
      ],
      if (b.kind == 'signature') ...[
        const SizedBox(height: 8),
        AppField(controller: _signer, label: t('الاسم', 'Name'), hint: '{{signer}}', onChanged: (v) => change(() => b.name = v)),
        AppField(controller: _title, label: t('الصفة', 'Title'), onChanged: (v) => change(() => b.title = v)),
      ],
      if (b.kind == 'text' || b.kind == 'signature') ...[
        _section(context, t('الخط', 'Font')),
        AppDropdown<String>(
          value: b.font.family,
          items: [for (final e in fontOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => change(() => b.font.family = v ?? ''),
        ),
        const SizedBox(height: 6),
        _slider(context, t('الحجم', 'Size'), b.font.size, 6, 40, (v) => change(() => b.font.size = v.roundToDouble())),
        _chips({'normal': t('عادي', 'Regular'), 'bold': t('عريض', 'Bold')}, b.font.weight, (v) => change(() => b.font.weight = v)),
        const SizedBox(height: 8),
        _swatches(b.font.color, (v) => change(() => b.font.color = v), allowDefault: true),
      ],
      if (b.kind == 'line') ...[
        _section(context, t('اللون', 'Colour')),
        _swatches(b.color, (v) => change(() => b.color = v), allowDefault: true),
      ],
      if (!b.isFlow && b.kind != 'line') ...[
        _section(context, t('المحاذاة', 'Alignment')),
        _chips({'start': t('بداية', 'Start'), 'center': t('وسط', 'Centre'), 'end': t('نهاية', 'End')}, b.align, (v) => change(() => b.align = v)),
      ],
      _section(context, t('الموضع والحجم', 'Position & size')),
      _slider(context, t('أفقي', 'X'), b.x * 100, 0, 100, (v) => change(() => (b..x = v / 100).clamp()), fmt: (v) => '${v.round()}%'),
      _slider(context, t('رأسي', 'Y'), b.y * 100, 0, 100, (v) => change(() => (b..y = v / 100).clamp()), fmt: (v) => '${v.round()}%'),
      _slider(context, t('العرض', 'Width'), b.w * 100, 6, 100, (v) => change(() => (b..w = v / 100).clamp()), fmt: (v) => '${v.round()}%'),
      if (b.kind != 'line') _slider(context, t('الارتفاع', 'Height'), b.h * 100, 2, 80, (v) => change(() => (b..h = v / 100).clamp()), fmt: (v) => '${v.round()}%'),
    ]);
  }

  Widget _pagePanel(BuildContext context, void Function(void Function()) change) {
    final d = _d;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section(context, t('الورقة', 'Paper')),
      AppDropdown<String>(
        value: d.page.size,
        items: [for (final s in exportPageSizes) DropdownMenuItem(value: s, child: Text(s))],
        onChanged: (v) => change(() => d.page.size = v ?? 'A4'),
      ),
      const SizedBox(height: 8),
      _chips({'portrait': t('رأسي', 'Portrait'), 'landscape': t('أفقي', 'Landscape')}, d.page.orientation, (v) => change(() => d.page.orientation = v)),
      _section(context, t('الهوامش (مم)', 'Margins (mm)')),
      _slider(context, t('أعلى', 'Top'), d.page.top, 0, 60, (v) => change(() => d.page.top = v.roundToDouble())),
      _slider(context, t('أسفل', 'Bottom'), d.page.bottom, 0, 60, (v) => change(() => d.page.bottom = v.roundToDouble())),
      _slider(context, t('يسار', 'Left'), d.page.left, 0, 60, (v) => change(() => d.page.left = v.roundToDouble())),
      _slider(context, t('يمين', 'Right'), d.page.right, 0, 60, (v) => change(() => d.page.right = v.roundToDouble())),
      AppSwitchTile(title: t('من اليمين إلى اليسار', 'Right to left'), value: d.rtl, dense: true, onChanged: (v) => change(() => d.rtl = v)),
      _section(context, t('الخط الأساسي', 'Base font')),
      AppDropdown<String>(
        value: d.fontFamily,
        items: [for (final e in exportFontLabels().entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => change(() => d.fontFamily = v ?? 'tajawal'),
      ),
      const SizedBox(height: 6),
      _slider(context, t('الحجم', 'Size'), d.fontSize, 6, 30, (v) => change(() => d.fontSize = v.roundToDouble())),
      _slider(context, t('تباعد الأسطر', 'Line spacing'), d.lineSpacing, 1, 2.5, (v) => change(() => d.lineSpacing = (v * 10).round() / 10), fmt: (v) => v.toStringAsFixed(1)),
      const SizedBox(height: 4),
      _swatches(d.fontColor, (v) => change(() => d.fontColor = v)),
      _section(context, t('رأس الصفحة', 'Header')),
      AppField(controller: _header, label: t('نص الرأس', 'Header text'), hint: '{{org}} · {{title}}', onChanged: (v) => change(() => d.headerText = v)),
      AppSwitchTile(title: t('إظهار التاريخ', 'Show the date'), value: d.showDate, dense: true, onChanged: (v) => change(() => d.showDate = v)),
      _section(context, t('تذييل الصفحة', 'Footer')),
      AppField(controller: _footer, label: t('نص التذييل', 'Footer text'), hint: '{{page}} / {{pages}}', onChanged: (v) => change(() => d.footerText = v)),
      AppSwitchTile(title: t('أرقام الصفحات', 'Page numbers'), value: d.showPageNumbers, dense: true, onChanged: (v) => change(() => d.showPageNumbers = v)),
    ]);
  }

  Widget _tablePanel(BuildContext context, void Function(void Function()) change) {
    final d = _d;
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section(context, t('النمط', 'Style')),
      _chips(exportTableStyleLabels(), d.table.style, (v) => change(() => d.table.style = v)),
      _section(context, t('لون الرأس', 'Header colour')),
      _swatches(d.table.headerColor, (v) => change(() {
            d.table.headerColor = v;
            d.table.headerTextColor = ['FFFFFF', 'F6F8FA'].contains(v) ? exportInk : 'FFFFFF';
          })),
      _section(context, t('لون نص الرأس', 'Header text colour')),
      _swatches(d.table.headerTextColor, (v) => change(() => d.table.headerTextColor = v)),
      _slider(context, t('حجم الخط', 'Font size'), d.table.fontSize, 5, 24, (v) => change(() => d.table.fontSize = v.roundToDouble())),
      _section(context, t('الأعمدة', 'Columns')),
      if (_data.columns.isEmpty)
        Text(t('لا أعمدة في هذه البيانات', 'This data has no columns'), style: appText(12, c: c.textMedium))
      else
        for (final col in _data.columns)
          AppSwitchTile(
            title: col.label(d.lang),
            dense: true,
            value: d.table.columns.isEmpty || d.table.columns.contains(col.id),
            onChanged: (v) => change(() {
              final cur = d.table.columns.isEmpty ? [for (final x in _data.columns) x.id] : [...d.table.columns];
              if (v) {
                if (!cur.contains(col.id)) cur.add(col.id);
              } else {
                cur.remove(col.id);
              }
              // keep the dataset order
              d.table.columns = [for (final x in _data.columns) if (cur.contains(x.id)) x.id];
            }),
          ),
    ]);
  }

  Widget _votesPanel(BuildContext context, void Function(void Function()) change) {
    final v = _d.votes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_d.itemsBlock == null)
        AppBanner(icon: Icons.info_outline_rounded, text: t('أضف عنصر «البنود» إلى الصفحة لتظهر نتائج التصويت.', 'Add the "Items" block to the page to print vote results.')),
      _section(context, t('موضع النتيجة', 'Result position')),
      _chips(exportVotePositionLabels(), v.position, (x) => change(() => v.position = x)),
      _section(context, t('الشكل', 'Style')),
      _chips(exportVoteStyleLabels(), v.style, (x) => change(() => v.style = x)),
      const SizedBox(height: 6),
      AppSwitchTile(title: t('الأعداد', 'Counts'), value: v.showCounts, dense: true, onChanged: (x) => change(() => v.showCounts = x)),
      AppSwitchTile(title: t('النسبة', 'Percent'), value: v.showPercent, dense: true, onChanged: (x) => change(() => v.showPercent = x)),
      AppSwitchTile(title: t('النتيجة', 'Outcome'), value: v.showOutcome, dense: true, onChanged: (x) => change(() => v.showOutcome = x)),
      AppSwitchTile(title: t('أسماء المصوّتين', 'Voters'), value: v.showVoters, dense: true, onChanged: (x) => change(() => v.showVoters = x)),
      _section(context, t('عينة', 'Sample')),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.colors.divider)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(exportSampleItems(_d.lang).first.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: exportFlutterFont(_d.fontFamily), fontSize: 12, fontWeight: FontWeight.w800, color: exportColor(_d.fontColor))),
              if (v.below) ...[const SizedBox(height: 6), VoteResultPreview(votes: v, result: exportSampleItems(_d.lang).first.votes!, lang: _d.lang, fontSize: 11, family: _d.fontFamily)],
            ]),
          ),
          if (v.beside) ...[
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 110), child: VoteResultPreview(votes: v, result: exportSampleItems(_d.lang).first.votes!, lang: _d.lang, fontSize: 11, beside: true, family: _d.fontFamily)),
          ],
        ]),
      ),
    ]);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap, this.label, this.border});
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label ?? '#${(color?.toARGB32() ?? 0) & 0xFFFFFF}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 28,
          padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(minWidth: 28),
          decoration: BoxDecoration(
            color: color ?? c.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? c.primary : (border ?? c.divider), width: selected ? 2 : 1),
          ),
          child: label == null ? null : Center(child: Text(label!, style: appText(11, w: FontWeight.w700, c: c.textMedium))),
        ),
      ),
    );
  }
}
