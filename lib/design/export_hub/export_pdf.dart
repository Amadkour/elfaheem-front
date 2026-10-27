// lib/design/export_hub/export_pdf.dart
//
// The Export Hub's PDF writer (package:pdf). Pure apart from `loadExportFonts`, which reads the bundled fonts
// through rootBundle — the writer itself takes the font bytes and the images (keyed by URL) so the tests can call
// it with files from disk. Page size / orientation / margins, header and footer with "{{page}} / {{pages}}",
// text · logo · signature · line blocks at their fractions, the table block flowing over pages with a repeating
// header, and the items block (one card per council item with the vote result beside / below / both).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_design.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Fonts
// ═════════════════════════════════════════════════════════════════════════════

/// (regular, bold) asset paths of a design font family. Bahij ships bold only; it is used for both weights.
(String, String) exportFontAssets(String family) => switch (family) {
      'bahij' => ('assets/fonts/Bahij_TheSansArabic-Bold.ttf', 'assets/fonts/Bahij_TheSansArabic-Bold.ttf'),
      'plex' => ('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf', 'assets/fonts/plex/IBMPlexSansArabic-Bold.ttf'),
      _ => ('assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/cert/Tajawal-Bold.ttf'),
    };

/// The TTF bytes per family the writer may need.
class ExportFontSet {
  ExportFontSet(this.regular, this.bold);
  final Map<String, ByteData> regular, bold;

  bool has(String family) => regular.containsKey(family) && bold.containsKey(family);

  /// The family's fonts, else the first loaded one.
  (ByteData, ByteData) of(String family) {
    if (has(family)) return (regular[family]!, bold[family]!);
    final k = regular.keys.first;
    return (regular[k]!, bold[k]!);
  }
}

/// Loads the bundled fonts of [families] (the design's `fontFamilies`).
Future<ExportFontSet> loadExportFonts(Iterable<String> families) async {
  final reg = <String, ByteData>{}, bold = <String, ByteData>{};
  for (final f in {...families, if (families.isEmpty) 'tajawal'}) {
    final (r, b) = exportFontAssets(f);
    reg[f] = await rootBundle.load(r);
    bold[f] = b == r ? reg[f]! : await rootBundle.load(b);
  }
  return ExportFontSet(reg, bold);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Writer
// ═════════════════════════════════════════════════════════════════════════════

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

/// Outcome → (fill, ink) hex.
(String, String) voteOutcomeColors(String outcome) => switch (outcome) {
      'approved' => ('DCFCE7', '166534'),
      'rejected' => ('FEE2E2', '991B1B'),
      'tied' => ('FEF3C7', '92400E'),
      'postponed' => ('DBEAFE', '1E40AF'),
      'no_quorum' => ('E2E8F0', '475569'),
      _ => ('F1F5F9', '475569'),
    };

const voteApproveHex = '16A34A', voteRejectHex = 'DC2626', voteAbstainHex = '94A3B8', voteRestHex = 'E2E8F0';

/// Labels the writers share (resolved by the design's language, not the UI language).
class ExportLabels {
  const ExportLabels(this.lang);
  final String lang;
  bool get ar => lang == 'ar';
  String l(String a, String e) => ar ? a : e;

  String get approve => l('موافق', 'Approve');
  String get reject => l('رافض', 'Reject');
  String get abstain => l('ممتنع', 'Abstain');
  String get eligible => l('من', 'of');
  String get voters => l('المصوّتون', 'Voters');
  String get decision => l('القرار', 'Decision');
  String get notes => l('ملاحظات', 'Notes');
  String get audit => l('سجل الإجراءات', 'Audit trail');
  String get result => l('النتيجة', 'Result');
  String get noRows => l('لا توجد صفوف', 'No rows');
  String get noItems => l('لا توجد بنود', 'No items');
  String get page => l('صفحة', 'Page');
  String get of => l('من', 'of');
  String get item => l('البند', 'Item');
  String outcome(String o) => switch (o) {
        'approved' => l('موافقة', 'Approved'),
        'rejected' => l('رفض', 'Rejected'),
        'tied' => l('تعادل', 'Tied'),
        'no_quorum' => l('لا نصاب', 'No quorum'),
        'postponed' => l('مؤجل', 'Postponed'),
        'pending' => l('قيد التصويت', 'Pending'),
        _ => o,
      };
  String vote(String v) => switch (v) { 'approve' => approve, 'reject' => reject, 'abstain' => abstain, _ => v };

  /// "موافق 9 · رافض 2 · ممتنع 1 · من 14"
  String counts(ExportVoteResult v) => [
        '$approve ${v.approve}',
        '$reject ${v.reject}',
        '$abstain ${v.abstain}',
        if (v.eligible > 0) '$eligible ${v.eligible}',
      ].join(' · ');
}

Future<Uint8List> exportPdf(ExportDesign d, ExportDataset data, ExportContent c, {required ExportFontSet fonts, Map<String, Uint8List> images = const {}}) async {
  final lang = c.langFor(d);
  final lb = ExportLabels(lang);
  final values = data.placeholderValues(lang);
  final rtl = d.rtl;
  final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final (pwMm, phMm) = d.page.mm;
  final format = PdfPageFormat(pwMm * PdfPageFormat.mm, phMm * PdfPageFormat.mm,
      marginTop: d.page.top * PdfPageFormat.mm, marginBottom: d.page.bottom * PdfPageFormat.mm, marginLeft: d.page.left * PdfPageFormat.mm, marginRight: d.page.right * PdfPageFormat.mm);
  final cw = format.availableWidth, ch = format.availableHeight;
  final (baseReg, baseBold) = fonts.of(d.fontFamily);
  final theme = pw.ThemeData.withFont(base: pw.Font.ttf(baseReg), bold: pw.Font.ttf(baseBold), fontFallback: [pw.Font.helvetica()]);
  final fontCache = <String, (pw.Font, pw.Font)>{};
  (pw.Font, pw.Font) family(String f) => fontCache.putIfAbsent(f.isEmpty ? d.fontFamily : f, () {
        final (r, b) = fonts.of(f.isEmpty ? d.fontFamily : f);
        return (pw.Font.ttf(r), pw.Font.ttf(b));
      });
  final ink = _pc(d.fontColor), line = _pc(exportLine);

  String fill(String s) => fillPlaceholders(s, values);

  pw.TextStyle style({BlockFont? f, double? size, bool? bold, String? color}) {
    final (r, b) = family(f?.family ?? '');
    final fs = size ?? f?.size ?? d.fontSize;
    return pw.TextStyle(
      font: r,
      fontBold: b,
      fontSize: fs,
      fontWeight: (bold ?? f?.bold ?? false) ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color != null ? _pc(color) : (f != null && f.color.isNotEmpty ? _pc(f.color) : ink),
      lineSpacing: fs * (d.lineSpacing - 1),
    );
  }

  pw.TextAlign align(String a) => switch (a) {
        'center' => pw.TextAlign.center,
        'end' => rtl ? pw.TextAlign.left : pw.TextAlign.right,
        _ => rtl ? pw.TextAlign.right : pw.TextAlign.left,
      };
  pw.Alignment boxAlign(String a) => switch (a) {
        'center' => pw.Alignment.topCenter,
        'end' => rtl ? pw.Alignment.topLeft : pw.Alignment.topRight,
        _ => rtl ? pw.Alignment.topRight : pw.Alignment.topLeft,
      };
  pw.MemoryImage? image(String url) {
    final bytes = images[url];
    if (url.isEmpty || bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  pw.Widget text(String s, {BlockFont? f, double? size, bool? bold, String? color, String a = 'start', int? maxLines}) =>
      pw.Text(s, textAlign: align(a), textDirection: dir, maxLines: maxLines, style: style(f: f, size: size, bold: bold, color: color));

  pw.Widget block(ExportBlock b) {
    final bw = b.w * cw, bh = b.h * ch;
    switch (b.kind) {
      case 'logo':
        final im = image(b.url);
        return pw.SizedBox(width: bw, height: bh, child: im == null ? pw.SizedBox() : pw.Align(alignment: boxAlign(b.align), child: pw.Image(im, fit: pw.BoxFit.contain)));
      case 'signature':
        final im = image(b.url);
        final name = fill(b.name).trim(), title = fill(b.title).trim();
        return pw.SizedBox(
          width: bw,
          height: bh,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Expanded(child: im == null ? pw.SizedBox() : pw.Align(alignment: boxAlign(b.align), child: pw.Image(im, fit: pw.BoxFit.contain))),
            if (name.isNotEmpty) text(name, f: b.font, bold: true, a: b.align, maxLines: 2),
            if (title.isNotEmpty) text(title, f: b.font, size: b.font.size * .85, color: exportMuted, a: b.align, maxLines: 2),
          ]),
        );
      case 'line':
        return pw.Container(width: bw, height: (bh).clamp(.5, 6).toDouble(), color: _pc(b.color.isEmpty ? exportLine : b.color));
      default:
        return pw.SizedBox(width: bw, child: text(fill(b.text), f: b.font, a: b.align));
    }
  }

  // the static blocks of one area, positioned relative to [top] (a fraction of the content height)
  pw.Widget area(List<ExportBlock> blocks, double top) {
    if (blocks.isEmpty) return pw.SizedBox();
    final height = blocks.map((b) => (b.y + b.h - top) * ch).reduce((a, b) => a > b ? a : b);
    return pw.SizedBox(
      width: cw,
      height: height.clamp(0, ch).toDouble(),
      child: pw.Stack(overflow: pw.Overflow.visible, children: [
        for (final b in blocks) pw.Positioned(left: b.x * cw, top: (b.y - top) * ch, child: block(b)),
      ]),
    );
  }

  // ── table
  pw.Widget table(ExportBlock tb) {
    final cols0 = data.columnsFor(d, c.columns);
    final cols = rtl ? cols0.reversed.toList() : cols0;
    final fs = d.table.fontSize;
    final head = d.table.headerColor, onHead = d.table.headerTextColor;
    final st = d.table.style;
    final pad = pw.EdgeInsets.symmetric(horizontal: fs * .5, vertical: fs * .4 * d.lineSpacing);
    double flex(ExportColumn col) => col.id == 'n' ? .45 : col.numeric ? .9 : (col.id == 'title' || col.id == 'subject' || col.id == 'body' ? 2.6 : 1.2);
    pw.Widget cell(String s, ExportColumn col, {bool header = false}) => pw.Container(
          padding: pad,
          alignment: col.numeric && !header ? (rtl ? pw.Alignment.centerLeft : pw.Alignment.centerRight) : (rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
          child: pw.Text(s,
              textDirection: dir,
              textAlign: col.numeric && !header ? (rtl ? pw.TextAlign.left : pw.TextAlign.right) : (rtl ? pw.TextAlign.right : pw.TextAlign.left),
              style: style(size: fs, bold: header, color: header ? (st == 'minimal' ? head : onHead) : null)),
        );
    final border = switch (st) {
      'grid' => pw.TableBorder.all(color: line, width: .5),
      'minimal' => pw.TableBorder(horizontalInside: pw.BorderSide(color: _pc('EEF2F7'), width: .4), bottom: pw.BorderSide(color: line, width: .6)),
      _ => pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: .4), bottom: pw.BorderSide(color: line, width: .4)),
    };
    final rows = data.rows;
    final body = rows.isEmpty || cols.isEmpty
        ? pw.Padding(padding: const pw.EdgeInsets.all(18), child: pw.Center(child: text(lb.noRows, color: exportMuted)))
        : pw.Table(
            columnWidths: {for (var k = 0; k < cols.length; k++) k: pw.FlexColumnWidth(flex(cols[k]))},
            border: border,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.TableRow(
                repeat: true,
                decoration: st == 'minimal'
                    ? pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _pc(head), width: 1.2)))
                    : pw.BoxDecoration(color: _pc(head)),
                children: [for (final col in cols) cell(col.label(lang), col, header: true)],
              ),
              for (var i = 0; i < rows.length; i++)
                pw.TableRow(
                  decoration: st == 'zebra' && i.isOdd ? pw.BoxDecoration(color: _pc('F6F8FA')) : null,
                  children: [for (final col in cols) cell(data.cell(col, rows[i][col.id]), col)],
                ),
            ],
          );
    return pw.Padding(padding: pw.EdgeInsets.only(left: tb.x * cw, right: (1 - tb.x - tb.w) * cw), child: body);
  }

  // ── votes
  final v = d.votes;
  pw.Widget voteBar(ExportVoteResult r, {double height = 6}) {
    final total = r.eligible > 0 ? r.eligible : (r.cast == 0 ? 1 : r.cast);
    int f(int n) => (n * 1000 / total).round().clamp(0, 1000);
    final rest = (1000 - f(r.approve) - f(r.reject) - f(r.abstain)).clamp(0, 1000);
    final parts = [(f(r.approve), voteApproveHex), (f(r.reject), voteRejectHex), (f(r.abstain), voteAbstainHex), (rest, voteRestHex)].where((p) => p.$1 > 0).toList();
    final ordered = rtl ? parts.reversed.toList() : parts;
    return pw.ClipRRect(
      horizontalRadius: height / 2,
      verticalRadius: height / 2,
      child: pw.Row(children: [for (final p in ordered) pw.Expanded(flex: p.$1, child: pw.Container(height: height, color: _pc(p.$2)))]),
    );
  }

  pw.Widget pill(String label, String outcome, {double size = 8.5}) {
    final (fill, inkHex) = voteOutcomeColors(outcome);
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: size * .8, vertical: size * .25),
      decoration: pw.BoxDecoration(color: _pc(fill), borderRadius: pw.BorderRadius.circular(size)),
      child: pw.Text(label, textDirection: dir, style: style(size: size, bold: true, color: inkHex)),
    );
  }

  /// The compact result at the side of an item.
  pw.Widget voteBeside(ExportVoteResult r) {
    final small = d.fontSize * .78;
    return pw.Column(crossAxisAlignment: rtl ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end, children: [
      if (v.showOutcome && v.style != 'text') pill(lb.outcome(r.outcome), r.outcome, size: small),
      if (v.showOutcome && v.style == 'text') text(lb.outcome(r.outcome), size: small, bold: true, color: voteOutcomeColors(r.outcome).$2, a: 'end'),
      if (v.style == 'bar') ...[pw.SizedBox(height: 3), pw.SizedBox(width: 90, child: voteBar(r, height: 5))],
      if (v.showPercent) ...[pw.SizedBox(height: 2), text(r.percentText, size: small, bold: true, a: 'end')],
      if (v.showCounts) ...[pw.SizedBox(height: 1), text('${r.approve} / ${r.reject} / ${r.abstain}', size: small * .95, color: exportMuted, a: 'end')],
    ]);
  }

  /// The full result under an item.
  pw.Widget voteBelow(ExportVoteResult r) {
    final small = d.fontSize * .82;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (v.style == 'bar') ...[voteBar(r), pw.SizedBox(height: 3)],
      pw.Row(children: [
        if (v.showOutcome && v.style == 'pill') ...[pill(lb.outcome(r.outcome), r.outcome, size: small), pw.SizedBox(width: 6)],
        pw.Expanded(
          child: text(
            [
              if (v.showOutcome && v.style != 'pill') '${lb.result}: ${lb.outcome(r.outcome)}',
              if (v.showCounts) lb.counts(r),
              if (v.showPercent) '${lb.approve} ${r.percentText}',
            ].join('  ·  '),
            size: small,
            color: exportMuted,
          ),
        ),
      ]),
    ]);
  }

  pw.Widget voters(ExportVoteResult r) => text(
        '${lb.voters}: ${r.voters.map((x) => '${x['name']} (${lb.vote('${x['vote']}')})').join('، ')}',
        size: d.fontSize * .78,
        color: exportMuted,
      );

  // ── items
  List<pw.Widget> items(ExportBlock ib) {
    final out = <pw.Widget>[];
    final left = ib.x * cw, right = (1 - ib.x - ib.w) * cw;
    pw.Widget pad(pw.Widget w) => pw.Padding(padding: pw.EdgeInsets.only(left: left, right: right), child: w);
    if (data.items.isEmpty) {
      return [pad(pw.Padding(padding: const pw.EdgeInsets.all(18), child: pw.Center(child: text(lb.noItems, color: exportMuted))))];
    }
    for (var i = 0; i < data.items.length; i++) {
      final it = data.items[i];
      final r = c.votes ? it.votes : null;
      // the reference is Latin ('W-2026-000041'): inside an Arabic line the bidi algorithm reorders it, so it is
      // its own left-to-right text next to the source instead of part of the sentence
      final source = it.source(lang);
      final metaLine = source;
      pw.Widget metaRow() => pw.Row(mainAxisAlignment: rtl ? pw.MainAxisAlignment.end : pw.MainAxisAlignment.start, children: [
            if (it.ref.isNotEmpty) pw.Text(it.ref, textDirection: pw.TextDirection.ltr, style: style(size: d.fontSize * .8, color: exportMuted)),
            if (it.ref.isNotEmpty && source.isNotEmpty) pw.Text('  ·  ', style: style(size: d.fontSize * .8, color: exportMuted)),
            if (source.isNotEmpty) pw.Flexible(child: text(source, size: d.fontSize * .8, color: exportMuted)),
          ]);
      final head = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            width: d.fontSize * 1.9,
            height: d.fontSize * 1.9,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: _pc(d.table.headerColor), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text('${i + 1}', style: style(size: d.fontSize * .9, bold: true, color: d.table.headerTextColor)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              text(it.title, bold: true, size: d.fontSize * 1.05),
              if (metaLine.isNotEmpty || it.ref.isNotEmpty) metaRow(),
              if (it.body.trim().isNotEmpty) ...[pw.SizedBox(height: 2), text(it.body.trim(), size: d.fontSize * .9, maxLines: 6)],
            ]),
          ),
          if (r != null && v.beside) ...[pw.SizedBox(width: 10), voteBeside(r)],
        ]),
        if (r != null && v.below) ...[pw.SizedBox(height: 5), voteBelow(r)],
      ]);
      // unsplittable: a card that does not fit moves to the next page whole (a Column inside a Container would be
      // split and leave an empty frame behind); a Row never spans pages in package:pdf
      out.add(pad(pw.Row(children: [
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
            decoration: pw.BoxDecoration(color: _pc('FAFBFC'), border: pw.Border.all(color: line, width: .5), borderRadius: pw.BorderRadius.circular(5)),
            child: head,
          ),
        ),
      ])));
      final extras = <pw.Widget>[
        if (r != null && v.showVoters && r.voters.isNotEmpty) voters(r),
        if (c.decisions && it.decision.isNotEmpty) text('${lb.decision}: ${it.decision}', size: d.fontSize * .88),
        if (c.notes && it.notes.isNotEmpty) text('${lb.notes}: ${it.notes}', size: d.fontSize * .88, color: exportMuted),
        if (c.audit && it.audit.isNotEmpty) ...[
          text(lb.audit, size: d.fontSize * .8, bold: true, color: exportMuted),
          for (final a in it.audit.take(12))
            text('• ${a['created_at'] ?? ''}  ${a['kind'] ?? ''}  ${a['actor'] is Map ? (a['actor'] as Map)['name'] ?? '' : a['actor'] ?? ''}  ${a['body'] ?? ''}'.trim(),
                size: d.fontSize * .76, color: exportMuted),
        ],
      ];
      for (final w in extras) {
        out.add(pad(pw.Padding(padding: const pw.EdgeInsets.fromLTRB(10, 2, 10, 0), child: w)));
      }
    }
    return out;
  }

  // ── header / footer
  final hasHeader = d.headerText.trim().isNotEmpty || d.showDate;
  final hasFooter = d.footerText.trim().isNotEmpty || d.showPageNumbers;
  String pages(String s, pw.Context ctx) => s.replaceAll('{{page}}', '${ctx.pageNumber}').replaceAll('{{pages}}', '${ctx.pagesCount}');
  pw.Widget header(pw.Context ctx) => !hasHeader
      ? pw.SizedBox()
      : pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .5))),
          child: pw.Row(children: [
            pw.Expanded(child: text(pages(fill(d.headerText), ctx), size: d.fontSize * .78, color: exportMuted, maxLines: 1)),
            if (d.showDate) text(values['date'] ?? '', size: d.fontSize * .78, color: exportMuted, a: 'end'),
          ]),
        );
  pw.Widget footer(pw.Context ctx) => !hasFooter
      ? pw.SizedBox()
      : pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.only(top: 3),
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line, width: .5))),
          child: pw.Row(children: [
            pw.Expanded(child: text(pages(fill(d.footerText), ctx), size: d.fontSize * .74, color: exportMuted, maxLines: 1)),
            if (d.showPageNumbers) text('${lb.page} ${ctx.pageNumber} ${lb.of} ${ctx.pagesCount}', size: d.fontSize * .74, color: exportMuted, a: 'end'),
          ]),
        );

  // ── pages
  final doc = pw.Document(theme: theme, title: data.title, author: values['org']?.isEmpty == false ? values['org'] : 'NextBrain', creator: 'NextBrain');
  final segs = d.segments;
  final content = <pw.Widget>[];
  var cursor = 0.0; // the fraction already printed
  for (final s in segs) {
    if (s.blocks.isNotEmpty) {
      final top = s.blocks.first.y;
      content.add(pw.SizedBox(height: ((top - cursor).clamp(0, 1) * ch).toDouble()));
      content.add(area(s.blocks, top));
      cursor = s.blocksBottom;
    }
    final f = s.flow;
    if (f != null) {
      content.add(pw.SizedBox(height: ((f.y - cursor).clamp(0, 1) * ch).toDouble()));
      if (f.kind == 'table') {
        content.add(table(f));
      } else {
        content.addAll(items(f));
      }
      cursor = f.y + f.h;
    }
  }
  doc.addPage(pw.MultiPage(
    pageFormat: format,
    textDirection: dir,
    maxPages: 2000,
    header: header,
    footer: footer,
    build: (_) => content,
  ));
  return doc.save();
}
