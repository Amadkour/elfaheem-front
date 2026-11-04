// The printed exam paper as PDF (package:pdf, A4), from an ExamPaperDoc (exam_paper.dart) in one of three designs:
//   Classic — a double frame on every page, Amiri, a centred crest (the logo, or the institution's initials), a formal
//             header table and an examiner's marks table;
//   Modern  — IBM Plex Sans Arabic with Bahij headings, a band in the institution's colour with the logo, info chips, tinted instruction card;
//   (package:pdf shapes Arabic with the fonts' presentation-form glyphs: only Amiri, Bahij and Plex have all of them.)
//   Minimal — IBM Plex Sans Arabic, black and white, thin rules (ink saving).
// Pages: a running header after page 1, "Page x of y" and "Please turn over" in the footer, "End of the exam" at the end.
// pw.Table ignores the text direction, so table columns are reversed by hand for Arabic (as the table export does).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../design/export/table_export_model.dart' show onColorHex, shadeHex, tintHex;
import 'exam_paper.dart';

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

/// [tpl] must be resolved (not auto / custom). [regular] / [bold]: the template's fonts (PaperStyle.of).
Future<Uint8List> examPaperPdf(ExamPaperDoc d, PaperTemplate tpl, {required ByteData regular, required ByteData bold}) async =>
    (await examPaperPdfMany([d], tpl, regular: regular, bold: bold)).bytes;

/// Several papers (per-student copies, versions) in ONE PDF; [pages] holds each paper's page count in order. A paper
/// with [ExamPaperDoc.qrPages] draws page p's QR in its footer; with [ExamPaperDoc.qrSlots] it only reserves the room,
/// so a counting pass lays out exactly like the real copy.
class PaperPdfResult {
  const PaperPdfResult(this.bytes, this.pages);
  final Uint8List bytes;
  final List<int> pages;
}

Future<PaperPdfResult> examPaperPdfMany(List<ExamPaperDoc> docs, PaperTemplate tpl, {required ByteData regular, required ByteData bold}) async {
  final doc = pw.Document(
    title: docs.isEmpty ? '' : docs.first.title,
    author: docs.isEmpty || docs.first.institution.isEmpty ? 'NextBrain' : docs.first.institution,
    creator: 'NextBrain',
    theme: pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold), fontFallback: [pw.Font.helvetica()]),
  );
  final pages = [for (final d in docs) _addPaper(doc, d, tpl)];
  return PaperPdfResult(await doc.save(), pages);
}

/// The QR's side in the footer (points); a reserved slot takes the same room as a real one.
const kPaperQrSize = 34.0;

int _addPaper(pw.Document doc, ExamPaperDoc d, PaperTemplate tpl) {
  var lastPage = 1;
  // pw.Context page numbers count the whole document: a paper in a merged PDF numbers its own pages from 1
  final offset = doc.document.pdfPageList.pages.length;
  final style = PaperStyle.of(tpl);
  final w = PaperWords(d.rtl);
  final accentHex = style.color ? d.accentHex : '1F2933';
  final accent = _pc(accentHex), accentDark = _pc(shadeHex(accentHex, .25)), tint = _pc(style.color ? tintHex(accentHex, .08) : 'F4F5F7');
  final ink = _pc('1F2933'), muted = _pc('6B7280'), line = _pc('B9C1CA'), faint = _pc('D7DDE3');
  final dir = d.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final classic = tpl == PaperTemplate.classic, modern = tpl == PaperTemplate.modern;
  const fs = 11.5;
  final logo = d.logo == null ? null : pw.MemoryImage(d.logo!);
  List<T> rtlCols<T>(List<T> cols) => d.rtl ? cols.reversed.toList() : cols;

  pw.Widget txt(String s, {double size = fs, bool bold = false, PdfColor? color, pw.TextAlign? align, double? height, int? maxLines}) => pw.Text(s,
      textAlign: align, maxLines: maxLines, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: color ?? ink, lineSpacing: height));

  // ── the crest: the logo, or the institution's initials in a ring
  pw.Widget crest(double size) {
    if (logo != null) return pw.SizedBox(width: size, height: size, child: pw.Image(logo, fit: pw.BoxFit.contain));
    final words = d.institution.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).toList();
    // the article ال is skipped ("مدرسة النور" → "من")
    final initials = words.map((x) => String.fromCharCode((x.startsWith('ال') && x.length > 2 ? x.substring(2) : x).runes.first)).join();
    return pw.Container(
      width: size, height: size, alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: modern ? PdfColors.white : accent, width: 1.6)),
      child: txt(initials.isEmpty ? '✦' : initials, size: size * .34, bold: true, color: modern ? PdfColors.white : accent),
    );
  }

  pw.Widget infoCell(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.RichText(
          textDirection: dir,
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontSize: 10, color: muted)),
            pw.TextSpan(text: value.isEmpty ? '—' : value, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: ink)),
          ]),
        ),
      );

  pw.Widget versionCell() => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: txt(w.version(d.version!), size: 11.5, bold: true, color: accentDark));

  // ── page-1 header
  pw.Widget header() {
    final infoStart = [infoCell(w.course, d.course), infoCell(w.date, d.dateText)];
    final infoEnd = [infoCell(w.duration, d.durationText), infoCell(w.total, fmtTotal(d.total)), if (d.version != null) versionCell()];
    if (classic) {
      return pw.Column(children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: infoStart)),
          pw.Column(children: [
            crest(54),
            pw.SizedBox(height: 4),
            if (d.institution.isNotEmpty) txt(d.institution, size: 13.5, bold: true, color: accentDark, align: pw.TextAlign.center),
          ]),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: infoEnd)),
        ]),
        pw.SizedBox(height: 8),
        pw.Container(height: 1.4, color: accent),
        pw.SizedBox(height: 1.6),
        pw.Container(height: .6, color: accent),
        pw.SizedBox(height: 8),
        txt(d.title, size: 17, bold: true, color: accentDark, align: pw.TextAlign.center),
        if (d.answerKey) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: txt(w.answerKey, size: 11, bold: true, color: PdfColors.red800)),
      ]);
    }
    if (modern) {
      final on = _pc(onColorHex(accentHex));
      pw.Widget chip(String label, String value) => pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: pw.BoxDecoration(color: tint, borderRadius: pw.BorderRadius.circular(10)),
            child: infoCell(label, value),
          );
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(12)),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (d.institution.isNotEmpty) txt(d.institution, size: 10.5, color: on),
                txt(d.title, size: 18, bold: true, color: on),
                if (d.answerKey) txt(w.answerKey, size: 10.5, bold: true, color: on),
              ]),
            ),
            pw.SizedBox(width: 10),
            logo != null
                ? pw.Container(
                    padding: const pw.EdgeInsets.all(5),
                    decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(10)),
                    child: crest(40))
                : crest(44),
          ]),
        ),
        pw.Wrap(spacing: 6, children: [
          chip(w.course, d.course),
          chip(w.date, d.dateText),
          chip(w.duration, d.durationText),
          chip(w.total, fmtTotal(d.total)),
          if (d.version != null) pw.Container(margin: const pw.EdgeInsets.only(top: 6), padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4), child: versionCell()),
        ]),
      ]);
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (d.institution.isNotEmpty) txt(d.institution, size: 10.5, color: muted),
            txt(d.title, size: 16, bold: true),
            if (d.answerKey) txt(w.answerKey, size: 10.5, bold: true),
          ]),
        ),
        if (logo != null) crest(36),
      ]),
      pw.SizedBox(height: 4),
      pw.Container(height: .8, color: ink),
      pw.SizedBox(height: 3),
      pw.Wrap(spacing: 14, children: [...infoStart, ...infoEnd]),
    ]);
  }

  // ── the student's box (two rows of label + writing space)
  pw.Widget studentBox() {
    pw.Widget field(String label, [String name = '']) => pw.Container(
          height: 26,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          alignment: d.rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          child: txt(name.isEmpty ? '$label:' : '$label: $name', size: 10, color: muted, maxLines: 1),
        );
    final border = pw.TableBorder.all(color: classic ? accent : line, width: classic ? .9 : .6);
    return pw.Table(
      border: border,
      columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
      children: [
        pw.TableRow(children: rtlCols([field(w.name, d.studentName), field(w.id)])),
        pw.TableRow(children: rtlCols([field(w.group), field(d.seatNumber ? w.seat : w.score)])),
      ],
    );
  }

  pw.Widget instructions() {
    if (d.instructions.isEmpty) return pw.SizedBox();
    final items = [
      for (var i = 0; i < d.instructions.length; i++)
        pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: txt('${i + 1}. ${d.instructions[i]}', size: 10.2)),
    ];
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: modern
          ? pw.BoxDecoration(color: tint, borderRadius: pw.BorderRadius.circular(10))
          : pw.BoxDecoration(border: pw.Border.all(color: classic ? accent : line, width: classic ? .8 : .5), borderRadius: pw.BorderRadius.circular(classic ? 2 : 6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [txt(w.instructions, size: 11, bold: true, color: accentDark), ...items]),
    );
  }

  // ── examiner's marks table: one column per part (or per question for a short single-part paper)
  pw.Widget marksTable() {
    final cols = <(String, double)>[];
    if (d.sections.length > 1) {
      for (var i = 0; i < d.sections.length; i++) {
        cols.add((d.sections[i].title.isEmpty ? w.sectionN(i) : d.sections[i].title, d.sections[i].points));
      }
    } else if (d.sections.isNotEmpty && d.sections.first.questions.length <= 10) {
      for (final q in d.sections.first.questions) {
        cols.add(('${q.number}', q.points));
      }
    }
    cols.add((w.sum, d.total));
    pw.Widget cell(String s, {bool head = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
          alignment: pw.Alignment.center,
          color: head ? _pc(style.color ? tintHex(accentHex, .14) : 'EEF0F3') : null,
          child: txt(s, size: 9.5, bold: head, align: pw.TextAlign.center),
        );
    final head = [cell(w.question, head: true), for (final c in cols) cell(c.$1, head: true)];
    final marks = [cell(w.marks, head: true), for (final c in cols) cell(fmtTotal(c.$2))];
    final score = [cell(w.score, head: true), for (final _ in cols) pw.SizedBox(height: 22)];
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Table(
        border: pw.TableBorder.all(color: classic ? accent : line, width: .6),
        columnWidths: {for (var i = 0; i <= cols.length; i++) i: pw.FlexColumnWidth(i == 0 ? 1.6 : 1)},
        children: [pw.TableRow(children: rtlCols(head)), pw.TableRow(children: rtlCols(marks)), pw.TableRow(children: rtlCols(score))],
      ),
      pw.SizedBox(height: 5),
      pw.Row(children: [
        pw.Expanded(child: txt('${w.examiner}: ..............................', size: 9.5, color: muted)),
        pw.Expanded(child: txt('${w.reviewer}: ..............................', size: 9.5, color: muted)),
      ]),
    ]);
  }

  // ── questions
  pw.Widget numberBadge(int n) => pw.Container(
        width: 22, height: 22, alignment: pw.Alignment.center,
        decoration: modern
            ? pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(7))
            : pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: classic ? accent : ink, width: 1)),
        child: txt('$n', size: 10, bold: true, color: modern ? _pc(onColorHex(accentHex)) : (classic ? accent : ink)),
      );

  pw.Widget pointsPill(double p) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: pw.BoxDecoration(
            color: modern ? tint : null, border: modern ? null : pw.Border.all(color: faint, width: .6), borderRadius: pw.BorderRadius.circular(8)),
        child: txt('(${w.pts(p)})', size: 9, color: muted),
      );

  pw.Widget mark({required bool on, bool square = false}) => pw.Container(
        width: 11, height: 11, alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          shape: square ? pw.BoxShape.rectangle : pw.BoxShape.circle,
          color: on ? accent : null,
          border: pw.Border.all(color: on ? accent : ink, width: .8),
        ),
      );

  pw.Widget keyBox(String s) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(top: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(color: _pc('FDF2F2'), border: pw.Border.all(color: PdfColors.red200, width: .6), borderRadius: pw.BorderRadius.circular(6)),
        child: txt(s.isEmpty ? '—' : s, size: 10.5, color: PdfColors.red900),
      );

  // the question's image under its prompt (bounded, never stretched); a failed fetch or an undecodable file prints a placeholder line
  pw.Widget? imageOf(PaperQuestion q) {
    if (!q.hasMedia) return null;
    if (q.image != null) {
      try {
        final image = pw.MemoryImage(q.image!);
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3, bottom: 5),
          child: pw.Align(
            alignment: d.rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            child: pw.ConstrainedBox(constraints: const pw.BoxConstraints(maxWidth: 300, maxHeight: 170), child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      } catch (_) {
        // falls through to the placeholder
      }
    }
    return pw.Padding(padding: const pw.EdgeInsets.only(top: 3, bottom: 4), child: txt(q.imagePlaceholder, size: 9.5, color: muted));
  }

  List<pw.Widget> body(PaperQuestion q) {
    final out = <pw.Widget>[];
    final img = imageOf(q);
    if (img != null) out.add(img);
    switch (q.type) {
      case 'mcq_single':
      case 'mcq_multi':
        final short = q.options.length >= 3 && q.options.every((o) => o.length <= 30);
        pw.Widget opt(int i) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                mark(on: d.answerKey && q.correct.contains(i), square: q.type == 'mcq_multi'),
                pw.SizedBox(width: 6),
                txt(choiceLabel(i, rtl: d.rtl), bold: true, size: 10.8),
                pw.SizedBox(width: 4),
                pw.Expanded(child: txt(q.options[i], size: 10.8, bold: d.answerKey && q.correct.contains(i))),
              ]),
            );
        if (q.type == 'mcq_multi') out.add(txt(w.chooseMany, size: 9.5, color: muted));
        if (short) {
          for (var i = 0; i < q.options.length; i += 2) {
            out.add(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: opt(i)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: i + 1 < q.options.length ? opt(i + 1) : pw.SizedBox()),
            ]));
          }
        } else {
          for (var i = 0; i < q.options.length; i++) {
            out.add(opt(i));
          }
        }
      case 'true_false':
        pw.Widget box(String label, bool value) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
              mark(on: d.answerKey && q.tfCorrect == value, square: true),
              pw.SizedBox(width: 5),
              txt(label, size: 10.8),
            ]);
        out.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Row(children: [box(w.trueW, true), pw.SizedBox(width: 28), box(w.falseW, false)])));
      case 'matching':
        // rows, not a pw.Table: a table may split across pages and leave the question's title behind
        final n = q.left.length > q.right.length ? q.left.length : q.right.length;
        out.add(txt(w.matchHint, size: 9.5, color: muted));
        for (var i = 0; i < n; i++) {
          final l = i < q.left.length ? q.left[i] : null;
          final k = l == null ? -1 : q.right.indexOf(q.pairs[l] ?? '');
          final keyLetter = k < 0 ? '' : choiceLetter(k, rtl: d.rtl);
          out.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(children: [
              pw.Expanded(child: l == null ? pw.SizedBox() : txt('${i + 1}. $l   (${d.answerKey ? ' $keyLetter ' : '      '})', size: 10.6)),
              pw.Container(width: .6, height: 14, color: faint),
              pw.SizedBox(width: 10),
              pw.Expanded(child: i < q.right.length ? txt('${choiceLabel(i, rtl: d.rtl)} ${q.right[i]}', size: 10.6) : pw.SizedBox()),
            ]),
          ));
        }
      case 'ordering':
        out.add(txt(w.orderHint, size: 9.5, color: muted));
        for (final it in q.items) {
          final pos = q.order.indexOf(it);
          out.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
            child: pw.Row(children: [
              pw.Container(
                width: 18, height: 16, alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: .7), borderRadius: pw.BorderRadius.circular(3)),
                child: d.answerKey && pos >= 0 ? txt('${pos + 1}', size: 9, bold: true, color: PdfColors.red900) : null,
              ),
              pw.SizedBox(width: 7),
              pw.Expanded(child: txt(it, size: 10.8)),
            ]),
          ));
        }
      case 'fill_blank':
        if (d.answerKey) out.add(keyBox(q.answerText));
      default:
        if (d.answerKey) out.add(keyBox(q.answerText));
    }
    return out;
  }

  pw.Widget answerLine() => pw.Container(
        height: 23,
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .6, style: pw.BorderStyle.dotted))),
      );

  // ── the answer table: question numbers x the letters to circle (choice questions)
  pw.Widget answerTable() {
    final rows = answerTableRows(answerTableEntries(d));
    if (rows.isEmpty) return pw.SizedBox();
    pw.Widget entry(AnswerTableEntry e) => pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: pw.Row(children: [
              pw.SizedBox(width: 20, child: txt('${e.number}', size: 9.5, bold: true)),
              for (var i = 0; i < e.letters.length; i++)
                pw.Container(
                  width: 15, height: 15, margin: const pw.EdgeInsets.only(right: 3), alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                      shape: e.multi ? pw.BoxShape.rectangle : pw.BoxShape.circle,
                      color: d.answerKey && e.correct.contains(i) ? accent : null,
                      border: pw.Border.all(color: d.answerKey && e.correct.contains(i) ? accent : ink, width: .7)),
                  child: txt(e.letters[i], size: 8, color: d.answerKey && e.correct.contains(i) ? PdfColors.white : ink),
                ),
            ]),
          ),
        );
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: classic ? accent : line, width: .7), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        txt(w.answerTableTitle, size: 10.5, bold: true, color: accentDark),
        pw.SizedBox(height: 4),
        for (final r in rows)
          pw.Row(children: [for (var i = 0; i < 3; i++) i < r.length ? entry(r[i]) : pw.Expanded(child: pw.SizedBox())]),
      ]),
    );
  }

  // ── a version's key (display strings from the server), the teacher's summary
  pw.Widget keySummary() => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: _pc('FDF2F2'), border: pw.Border.all(color: PdfColors.red200, width: .6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          txt(w.keySummaryTitle, size: 10.5, bold: true, color: PdfColors.red900),
          pw.SizedBox(height: 3),
          pw.Wrap(spacing: 14, runSpacing: 2, children: [for (final k in d.keySummary) txt('${k.n}: ${k.display}', size: 10, color: PdfColors.red900)]),
        ]),
      );

  final tableOn = d.answerTable != AnswerTablePlace.none && answerTableEntries(d).isNotEmpty;
  final content = <pw.Widget>[
    pw.SizedBox(height: 10),
    if (!d.answerKey) ...[studentBox(), pw.SizedBox(height: 9)],
    instructions(),
    if (!d.answerKey && !tplIsMinimal(tpl)) ...[pw.SizedBox(height: 9), marksTable()],
    if (d.answerKey && d.keySummary.isNotEmpty) ...[pw.SizedBox(height: 9), keySummary()],
    if (tableOn && d.answerTable == AnswerTablePlace.start) ...[pw.SizedBox(height: 9), answerTable()],
    pw.SizedBox(height: 12),
  ];
  for (var si = 0; si < d.sections.length; si++) {
    final s = d.sections[si];
    // the part's heading travels with its first question, so it never ends a page alone
    final heading = <pw.Widget>[];
    if (d.sections.length > 1 || s.title.isNotEmpty) {
      heading.add(pw.Container(
        margin: pw.EdgeInsets.only(top: si == 0 ? 0 : 10, bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: modern
            ? pw.BoxDecoration(color: tint, borderRadius: pw.BorderRadius.circular(8))
            : pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: classic ? accent : ink, width: 1))),
        child: pw.Row(children: [
          pw.Expanded(child: txt(s.title.isEmpty ? w.sectionN(si) : s.title, size: 12.5, bold: true, color: accentDark)),
          if (d.showPoints) txt(w.pts(s.points), size: 9.5, color: muted),
        ]),
      ));
      if (s.instructions.isNotEmpty) heading.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: txt(s.instructions, size: 10, color: muted)));
    }
    for (final q in s.questions) {
      final prompt = q.type == 'fill_blank' ? blankPrompt(q.prompt, q.blanks) : q.prompt;
      final lead = q == s.questions.first ? heading : const <pw.Widget>[];
      // Inseparable: a Column may otherwise be split across pages, leaving the title or heading behind
      content.add(pw.Inseparable(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        ...lead,
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          numberBadge(q.number),
          pw.SizedBox(width: 8),
          pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: txt(prompt, bold: true, height: 2))),
          if (d.showPoints) ...[pw.SizedBox(width: 6), pointsPill(q.points)],
        ]),
        pw.Padding(
          padding: pw.EdgeInsets.only(left: d.rtl ? 0 : 30, right: d.rtl ? 30 : 0, top: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: body(q)),
        ),
      ])));
      // ruled lines one by one, so a long essay may continue on the next page
      if (!d.answerKey) {
        for (var i = 0; i < q.lines; i++) {
          content.add(pw.Padding(padding: pw.EdgeInsets.only(left: d.rtl ? 0 : 30, right: d.rtl ? 30 : 0), child: answerLine()));
        }
      }
    }
  }
  if (tableOn && d.answerTable == AnswerTablePlace.end) content.addAll([pw.SizedBox(height: 14), answerTable()]);
  content.add(pw.Padding(
    padding: const pw.EdgeInsets.only(top: 22),
    child: pw.Row(children: [
      pw.Expanded(child: pw.Container(height: .6, color: faint)),
      pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 10), child: txt(w.end, size: 10.5, bold: true, color: accentDark)),
      pw.Expanded(child: pw.Container(height: .6, color: faint)),
    ]),
  ));

  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(40, classic ? 40 : 32, 40, classic ? 34 : 28),
      textDirection: dir,
      buildBackground: classic
          ? (c) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Container(
                  margin: const pw.EdgeInsets.all(18),
                  padding: const pw.EdgeInsets.all(2.5),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: accent, width: 1.8)),
                  child: pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(color: accent, width: .6))),
                ),
              )
          : null,
    ),
    maxPages: 500,
    header: (c) => c.pageNumber - offset == 1
        ? header()
        : pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: classic || modern ? accent : ink, width: .8))),
            child: pw.Row(children: [
              pw.Expanded(child: txt(d.title, size: 9.5, bold: true, color: accentDark)),
              if (d.studentName.isNotEmpty) txt(d.studentName, size: 9, bold: true),
              if (d.version != null) ...[pw.SizedBox(width: 8), txt(w.version(d.version!), size: 9, bold: true, color: accentDark)],
              if (d.course.isNotEmpty) ...[pw.SizedBox(width: 8), txt(d.course, size: 9, color: muted)],
            ]),
          ),
    footer: (c) {
      final no = c.pageNumber - offset, total = c.pagesCount - offset;
      if (no > lastPage) lastPage = no;
      final payload = no <= d.qrPages.length ? d.qrPages[no - 1] : null;
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(child: txt(paperTurnOver(no, total) ? w.turnOver : '', size: 8.5, color: muted)),
          txt(w.page(no, total), size: 8.5, color: muted),
          if (d.qrReserved) ...[
            pw.SizedBox(width: 10),
            pw.SizedBox(
              width: kPaperQrSize, height: kPaperQrSize,
              child: payload == null ? null : pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: payload, drawText: false, color: PdfColors.black),
            ),
          ],
        ]),
      );
    },
    build: (_) => content,
  ));
  return lastPage;
}

/// "Please turn over" belongs on every page of a paper but its last ([total] = that paper's own page count).
bool paperTurnOver(int no, int total) => no < total;

bool tplIsMinimal(PaperTemplate t) => t == PaperTemplate.minimal;

String fmtTotal(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
