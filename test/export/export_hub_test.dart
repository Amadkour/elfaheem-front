// Export Hub (lib/design/export_hub/): the design document, the presets, placeholders, the dataset, and the three
// writers. `EXPORT_SAMPLES=<dir> flutter test test/export/export_hub_test.dart` writes hub_*.pdf / .docx / .xlsx there.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_docx.dart';
import 'package:flutter_education_app/design/export_hub/export_pdf.dart';
import 'package:flutter_education_app/design/export_hub/export_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Map<String, String> unzip(Uint8List bytes) =>
    {for (final f in ZipDecoder().decodeBytes(bytes)) if (f.isFile) f.name: f.name.endsWith('.png') ? '<png ${f.content.length}>' : utf8.decode(f.content)};

ExportFontSet? _fonts;
ExportFontSet fonts() {
  if (_fonts != null) return _fonts!;
  ByteData load(String p) => ByteData.sublistView(File(p).readAsBytesSync());
  final reg = <String, ByteData>{}, bold = <String, ByteData>{};
  for (final f in exportFontFamilies) {
    final (r, b) = exportFontAssets(f);
    reg[f] = load(r);
    bold[f] = load(b);
  }
  return _fonts = ExportFontSet(reg, bold);
}

Uint8List logoPng() {
  final im = img.Image(width: 80, height: 40);
  img.fill(im, color: img.ColorRgb8(15, 118, 110));
  return Uint8List.fromList(img.encodePng(im));
}

void sample(String name, Uint8List bytes) {
  final dir = Platform.environment['EXPORT_SAMPLES'];
  if (dir == null || dir.isEmpty) return;
  File('$dir${Platform.pathSeparator}$name').writeAsBytesSync(bytes);
}

/// A council design with a logo + signature image so the picture paths are exercised.
ExportDesign councilDesign(String lang) {
  final d = ExportDesign.standard('council', lang);
  d.blocks.firstWhere((b) => b.kind == 'logo').url = 'https://x/logo.png';
  d.blocks.firstWhere((b) => b.kind == 'signature').url = '/api/v1/org/files/sig.png';
  return d;
}

const images = <String, Uint8List>{};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('design', () {
    test('round-trips through JSON, clamps blocks, keeps the spec shape', () {
      final d = ExportDesign.standard('items', 'ar');
      final j = jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
      expect(j['version'], 2);
      expect(j['rtl'], isTrue);
      expect((j['page'] as Map)['margins'], containsPair('top', 16));
      expect((j['font'] as Map)['color'], startsWith('#'));
      expect((j['table'] as Map)['header_color'], '#0F766E');
      expect((j['votes'] as Map)['position'], isIn(exportVotePositions));
      final back = ExportDesign.fromJson(j);
      expect(back.blocks.length, d.blocks.length);
      expect(back.toJson(), d.toJson());
      expect(back.tableBlock, isNotNull);
      expect(back.after.map((b) => b.kind), everyElement('signature'));
      expect(back.before.every((b) => b.y < back.tableBlock!.y), isTrue);

      final b = ExportBlock(id: 'x', kind: 'text', x: .97, y: 1.4, w: .3, h: 2)..clamp();
      expect(b.x + b.w, lessThanOrEqualTo(1));
      expect(b.y + b.h, lessThanOrEqualTo(1));
      b.snap();
      expect((b.x * 50).round() / 50, closeTo(b.x, 1e-9));
      final bad = ExportDesign.fromJson({
        'page': {'size': 'Tabloid', 'orientation': 'sideways', 'margins': {'top': 999}},
        'font': {'family': 'comic', 'size': 400, 'color': 'red'},
        'table': {'style': 'fancy', 'header_color': 'nope'},
        'votes': {'position': 'left', 'style': 'neon'},
        'blocks': [
          {'id': 'q', 'kind': 'video', 'x': 5, 'y': 5, 'w': 0, 'h': 0},
        ],
      });
      expect(bad.page.size, 'A4');
      expect(bad.page.orientation, 'portrait');
      expect(bad.page.top, 60);
      expect(bad.fontFamily, 'tajawal');
      expect(bad.fontSize, 30);
      expect(bad.fontColor, exportInk);
      expect(bad.table.style, 'zebra');
      expect(bad.table.headerColor, exportBrand);
      expect(bad.votes.position, 'below');
      expect(bad.votes.style, 'bar');
      expect(bad.blocks.single.kind, 'text');
      expect(bad.blocks.single.x + bad.blocks.single.w, lessThanOrEqualTo(1));
    });

    test('one table / items block, ids are unique, segments split around the flow blocks', () {
      final d = ExportDesign(blocks: []);
      final t1 = d.add('table');
      expect(d.add('table'), same(t1));
      final it = d.add('items');
      expect(d.add('items'), same(it));
      d.add('text');
      d.add('logo');
      d.add('signature');
      d.add('line');
      expect(d.blocks.map((b) => b.id).toSet().length, d.blocks.length);
      expect(d.flows.length, 2);
      final segs = d.segments;
      expect(segs.length, 3);
      expect(segs[0].flow, isNotNull);
      expect(segs[1].flow, isNotNull);
      expect(segs.last.flow, isNull);
      expect(segs.last.blocks.map((b) => b.kind), contains('signature'));
      d.remove(it.id);
      expect(d.itemsBlock, isNull);
      expect(d.copy().toJson(), d.toJson());
      expect(d.fontFamilies, contains('tajawal'));
    });

    test('standard presets differ between Arabic and English and between modules', () {
      for (final m in exportModules) {
        final ar = ExportDesign.standard(m, 'ar'), en = ExportDesign.standard(m, 'en');
        expect(ar.rtl, isTrue);
        expect(en.rtl, isFalse);
        expect(ar.toJson(), isNot(equals(en.toJson())));
        // not a mirror: the Arabic logo is centred, the English one sits at the start with the name beside it
        expect(ar.blocks.firstWhere((b) => b.kind == 'logo').align, 'center');
        expect(en.blocks.firstWhere((b) => b.kind == 'logo').x, 0);
        expect(en.blocks.firstWhere((b) => b.kind == 'logo').align, 'start');
        final flows = ar.flows.map((b) => b.kind).toList();
        expect(flows, m == 'council' || m == 'minutes' ? ['items'] : ['table']);
      }
      final council = ExportDesign.standard('council', 'ar');
      expect(council.votes.position, 'both');
      expect(council.blocks.where((b) => b.kind == 'signature').length, 2);
      final minutes = ExportDesign.standard('minutes', 'en');
      expect(minutes.votes.position, 'below');
      expect(minutes.votes.showVoters, isTrue);
      expect(minutes.blocks.any((b) => b.text.contains('Minutes')), isTrue);
    });
  });

  group('placeholders and dataset', () {
    test('fill known keys incl. meta.*, keep unknown ones, dataset values', () {
      expect(fillPlaceholders('{{org}} / {{ dept }} / {{meta.x}} / {{oops}}', {'org': 'U', 'dept': 'D', 'meta.x': '7'}), 'U / D / 7 / {{oops}}');
      final ds = exportSampleDataset('council', 'en');
      final v = ds.placeholderValues('en');
      expect(v['org'], 'Al Noor University');
      expect(v['council'], 'Computer Science council');
      expect(v['count'], '2');
      expect(v['meta.session'], 'Session 12');
      expect(v['session_date'], isNotEmpty);
      expect(v['page'], '{{page}}'); // filled by the writers per page
      expect(ds.labelFor('ref', 'ar'), 'المرجع');
      expect(ds.labelFor('ref', 'en'), 'Ref');
      expect(ds.hasVotes, isTrue);
      expect(ds.cell(ds.column('created_at')!, '2026-10-12'), contains('2026'));
      expect(ds.cell(ds.column('n')!, 1), '1');
    });

    test('fromJson reads the server shape; fromTable keeps columns and rows', () {
      final ds = ExportDataset.fromJson({
        'module': 'council',
        'title': 'Session',
        'lang': 'ar',
        'meta': {'org': 'U', 'count': 1},
        'columns': [
          {'id': 'ref', 'label_ar': 'المرجع', 'label_en': 'Ref', 'type': 'text'},
        ],
        'rows': [
          {'ref': 'W-1'},
        ],
        'items': [
          {
            'item': {'ref': 'W-1', 'title': 'T', 'source': {'dept': {'name_ar': 'ق', 'name_en': 'D'}, 'user': {'name': 'P'}}},
            'votes': {'approve': 3, 'reject': 1, 'abstain': 0, 'eligible': 5, 'approve_pct': 75, 'outcome': 'approved', 'votes': [{'user': {'name': 'A'}, 'vote': 'approve'}]},
            'decision': {'outcome': 'approved', 'note': 'ok'},
            'notes': 'n',
            'audit': [{'kind': 'voted', 'actor': {'name': 'A'}, 'created_at': '2026-10-20'}],
          },
        ],
      });
      expect(ds.items.single.votes!.approve, 3);
      expect(ds.items.single.votes!.voters.single['name'], 'A');
      expect(ds.items.single.decision, 'approved — ok');
      expect(ds.items.single.source('en'), 'D · P');
      expect(ds.items.single.source('ar'), 'ق · P');
      expect(ds.hasAudit, isTrue);
      final back = ExportDataset.fromJson(ds.toJson());
      expect(back.items.single.votes!.outcome, 'approved');

      final e = AppTableExport(
        id: 'payouts',
        title: 'Payouts',
        brand: 'Academy',
        subtitle: 'October',
        columns: const [
          AppExportColumn('name', 'Teacher'),
          AppExportColumn('amount', 'Amount', type: AppColType.money, currency: 'EGP'),
          AppExportColumn('status', 'Status', type: AppColType.status, statusLabels: {'paid': 'Paid'}),
        ],
        rows: [
          {'name': 'A', 'amount': 10, 'status': 'paid'},
          {'name': 'B', 'amount': 20.5, 'status': 'pending'},
        ],
        rtl: false,
      );
      final t = ExportDataset.fromTable(e);
      expect(t.module, 'table');
      expect(t.prefId, 'table.payouts');
      expect(t.columns.map((c) => c.id), ['name', 'amount', 'status']);
      expect(t.column('amount')!.type, 'money');
      expect(t.rows.length, 2);
      expect(t.rows.first['status'], 'Paid'); // status labels resolved
      expect(t.meta['org'], 'Academy');
      expect(t.meta['period'], 'October');
      expect(t.labelFor('name', 'ar'), 'Teacher');
    });

    test('content switches round-trip and resolve the languages', () {
      final c = ExportContent(langs: 'both', audit: true, columns: ['ref']);
      expect(c.languages, ['ar', 'en']);
      final back = ExportContent.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.audit, isTrue);
      expect(back.columns, ['ref']);
      expect(ExportContent(langs: 'en').languages, ['en']);
      expect(c.langFor(ExportDesign.standard('items', 'en')), 'en');
      expect(c.langFor(ExportDesign.standard('items', 'ar')), 'ar');
    });
  });

  group('PDF', () {
    test('every preset, both languages, with and without rows', () async {
      for (final m in exportModules) {
        for (final lang in const ['ar', 'en']) {
          final d = ExportDesign.standard(m, lang);
          final ds = exportSampleDataset(m, lang);
          final pdf = await exportPdf(d, ds, ExportContent(), fonts: fonts());
          expect(String.fromCharCodes(pdf.take(5)), '%PDF-', reason: '$m/$lang');
          final empty = ExportDataset(module: m, title: 'Empty', lang: lang, columns: ds.columns);
          final pdf2 = await exportPdf(d, empty, ExportContent(), fonts: fonts());
          expect(String.fromCharCodes(pdf2.take(5)), '%PDF-');
        }
      }
      sample('hub_items_ar.pdf', await exportPdf(ExportDesign.standard('items', 'ar'), exportSampleDataset('items', 'ar'), ExportContent(), fonts: fonts()));
    });

    test('the items block with every votes position / style, voters, audit, logo and signature images', () async {
      final ds = exportSampleDataset('council', 'ar');
      final many = ExportDataset(module: 'council', title: ds.title, lang: 'ar', meta: ds.meta, columns: ds.columns, rows: ds.rows, items: [for (var i = 0; i < 25; i++) ...ds.items]);
      for (final pos in exportVotePositions) {
        for (final style in exportVoteStyles) {
          final d = councilDesign('ar')
            ..votes.position = pos
            ..votes.style = style
            ..votes.showVoters = true;
          final pdf = await exportPdf(d, many, ExportContent(audit: true), fonts: fonts(), images: {'https://x/logo.png': logoPng(), '/api/v1/org/files/sig.png': logoPng()});
          expect(String.fromCharCodes(pdf.take(5)), '%PDF-', reason: '$pos/$style');
          if (pos == 'both' && style == 'bar') sample('hub_council_ar.pdf', pdf);
        }
      }
      final en = await exportPdf(councilDesign('en'), exportSampleDataset('council', 'en'), ExportContent(votes: false), fonts: fonts());
      expect(String.fromCharCodes(en.take(5)), '%PDF-');
      sample('hub_council_en.pdf', en);
    });

    test('page sizes, landscape, every font family, a broken image is skipped', () async {
      for (final size in exportPageSizes) {
        for (final family in exportFontFamilies) {
          final d = ExportDesign.standard('items', 'en')
            ..page.size = size
            ..page.orientation = 'landscape'
            ..fontFamily = family;
          d.blocks.first.font.family = family == 'plex' ? 'bahij' : 'plex';
          d.blocks.firstWhere((b) => b.kind == 'logo').url = 'bad';
          final pdf = await exportPdf(d, exportSampleDataset('items', 'en'), ExportContent(), fonts: fonts(), images: {'bad': Uint8List.fromList([1, 2, 3])});
          expect(String.fromCharCodes(pdf.take(5)), '%PDF-', reason: '$size/$family');
        }
      }
    });
  });

  group('Word', () {
    test('a valid package: section, header / footer fields, Arabic text, the table rows, the items and outcomes', () {
      final ar = unzip(exportDocx(councilDesign('ar'), exportSampleDataset('council', 'ar'), ExportContent(audit: true), images: {'https://x/logo.png': logoPng()}));
      final doc = ar['word/document.xml']!;
      expect(doc, contains('<w:bidi/>'));
      expect(doc, contains('جامعة النور'));
      expect(doc, contains('اعتماد نتائج الفصل الدراسي الأول'));
      expect(doc, contains('موافقة')); // the outcome
      expect(doc, contains('رفض'));
      expect(doc, contains('w:pgSz w:w="11906"'));
      expect(doc, isNot(contains('{{')));
      expect(doc, contains('r:embed="rImg1"'));
      expect(ar.keys, contains('word/media/img1.png'));
      expect(ar['word/_rels/document.xml.rels'], contains('media/img1.png'));
      expect(ar['word/header1.xml'], contains('<w:hdr'));
      expect(ar['word/footer1.xml'], contains('NUMPAGES'));
      expect(ar['word/footer1.xml'], contains(' PAGE '));
      expect(ar['[Content_Types].xml'], contains('header1.xml'));

      final en = unzip(exportDocx(ExportDesign.standard('items', 'en')..page.orientation = 'landscape'..headerText = 'p {{page}}/{{pages}}', exportSampleDataset('items', 'en'), ExportContent()));
      final d2 = en['word/document.xml']!;
      expect(d2, isNot(contains('<w:bidi/>')));
      expect(d2, contains('w:orient="landscape"'));
      expect(d2, contains('<w:tblHeader/>'));
      expect(d2, contains('Approve term results'));
      expect(d2, contains('Requests report'));
      expect(en['word/header1.xml'], contains('<w:fldSimple w:instr=" PAGE "'));
      expect(en['word/header1.xml'], contains('NUMPAGES'));
      sample('hub_items_en.docx', exportDocx(ExportDesign.standard('items', 'en'), exportSampleDataset('items', 'en'), ExportContent()));
      sample('hub_council_ar.docx', exportDocx(councilDesign('ar'), exportSampleDataset('council', 'ar'), ExportContent(audit: true), images: {'https://x/logo.png': logoPng()}));
    });

    test('votes beside → a two-column table per item; below → a result paragraph; switched off → nothing', () {
      final ds = exportSampleDataset('council', 'en');
      String body(String pos, {bool votes = true, String style = 'bar'}) =>
          unzip(exportDocx(ExportDesign.standard('council', 'en')..votes.position = pos..votes.style = style, ds, ExportContent(votes: votes)))['word/document.xml']!;
      final beside = body('beside');
      expect(beside, contains('<w:gridCol')); // the item | result table
      expect(beside, contains('81.8%'));
      final below = body('below', style: 'text');
      expect(below, contains('Result: Approved'));
      expect(below, contains('Approve 9'));
      final none = body('both', votes: false);
      expect(none, isNot(contains('81.8%')));
      expect(none, isNot(contains('Approve 9')));
      for (final st in exportTableStyles) {
        final x = unzip(exportDocx(ExportDesign.standard('items', 'en')..table.style = st, exportSampleDataset('items', 'en'), ExportContent()))['word/document.xml']!;
        expect(x, contains('<w:tbl>'), reason: st);
      }
    });
  });

  group('Excel', () {
    test('sheet1 holds the rows with formats and a frozen header; Votes sheet only with vote results', () {
      final ds = exportSampleDataset('council', 'ar');
      final withVotes = unzip(exportXlsx(ExportDesign.standard('council', 'ar'), ds, ExportContent()));
      final s1 = withVotes['xl/worksheets/sheet1.xml']!;
      expect(s1, contains('rightToLeft="1"'));
      expect(s1, contains('state="frozen"'));
      expect(s1, contains('المرجع'));
      expect(s1, contains('W-2026-000041'));
      expect(s1, contains('<v>1</v>')); // the integer column is a number
      expect(withVotes['xl/styles.xml'], contains('yyyy-mm-dd'));
      expect(withVotes.keys, contains('xl/worksheets/sheet2.xml'));
      final votes = withVotes['xl/worksheets/sheet2.xml']!;
      expect(votes, contains('موافقة'));
      expect(votes, contains('<v>9</v>'));
      expect(votes, contains('<v>0.818</v>'));
      expect(withVotes['xl/workbook.xml'], contains('التصويت'));
      expect(withVotes['[Content_Types].xml'], contains('sheet2.xml'));

      final noVotes = unzip(exportXlsx(ExportDesign.standard('council', 'en'), exportSampleDataset('council', 'en'), ExportContent(votes: false)));
      expect(noVotes.keys, isNot(contains('xl/worksheets/sheet2.xml')));
      expect(noVotes['xl/workbook.xml'], isNot(contains('Votes')));
      final plain = unzip(exportXlsx(ExportDesign.standard('items', 'en'), exportSampleDataset('items', 'en'), ExportContent()));
      expect(plain.keys, isNot(contains('xl/worksheets/sheet2.xml')));
      expect(plain['xl/worksheets/sheet1.xml'], isNot(contains('rightToLeft')));
      expect(plain['xl/worksheets/sheet1.xml'], contains('Requests report'));
      final empty = unzip(exportXlsx(ExportDesign.standard('items', 'en'), ExportDataset(module: 'items', title: 'E', lang: 'en', columns: ds.columns), ExportContent()));
      expect(empty['xl/worksheets/sheet1.xml'], contains('No rows'));
      sample('hub_council_ar.xlsx', exportXlsx(ExportDesign.standard('council', 'ar'), ds, ExportContent()));
    });

    test('a column subset from the content switches wins over the design', () {
      final d = ExportDesign.standard('items', 'en')..table.columns = ['ref', 'title'];
      final ds = exportSampleDataset('items', 'en');
      expect(ds.columnsFor(d).map((c) => c.id), ['ref', 'title']);
      expect(ds.columnsFor(d, ['status']).map((c) => c.id), ['status']);
      expect(ds.columnsFor(d, ['nope']).map((c) => c.id), ds.columns.map((c) => c.id)); // unknown → every column
      final x = unzip(exportXlsx(d, ds, ExportContent(columns: ['status'])))['xl/worksheets/sheet1.xml']!;
      expect(x, contains('Status'));
      expect(x, isNot(contains('W-2026-000041')));
    });
  });

  group('bidi fixes seen in the sample PDFs', () {
    test('dates print with an Arabic month in Arabic layouts and a Latin one in English', () {
      final d = DateTime.utc(2026, 10, 27, 9);
      expect(exportDateText(d, 'ar'), contains('أكتوبر'));
      expect(exportDateText(d, 'ar'), contains('2026'));
      expect(exportDateText(d, 'en'), contains('Oct'));
      expect(exportDateText(null, 'ar'), '');
    });

    test('the Word writer wraps the Latin reference in LRM marks inside Arabic paragraphs only', () {
      final ar = ExportDesign.standard('council', 'ar');
      final en = ExportDesign.standard('council', 'en');
      final ds = exportSampleDataset('council', 'ar');
      final xAr = unzip(exportDocx(ar, ds, ExportContent(votes: true)))['word/document.xml']!;
      final xEn = unzip(exportDocx(en, exportSampleDataset('council', 'en'), ExportContent(votes: true)))['word/document.xml']!;
      expect(xAr, contains('‎W-2026-000041‎'));
      expect(xEn, isNot(contains('‎')));
    });

    test('a council PDF with many items still renders (cards move whole to the next page)', () async {
      final d = ExportDesign.standard('council', 'ar');
      final base = exportSampleDataset('council', 'ar');
      final many = ExportDataset(module: base.module, title: base.title, lang: base.lang, meta: base.meta, columns: base.columns, rows: base.rows,
          items: [for (var i = 0; i < 40; i++) ...base.items]);
      final bytes = await exportPdf(d, many, ExportContent(votes: true, notes: true, decisions: true), fonts: fonts());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(20000));
    });
  });
}
